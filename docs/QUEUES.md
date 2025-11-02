# Queue System Documentation

## Overview

DocuTab uses Asynq and Redis to provide a robust, persistent task queue system for asynchronous job processing. This document describes the queue architecture, configuration, and operational details.

## Architecture

### Components

1. **Redis** - Message broker and persistence layer
   - Stores queued tasks
   - Maintains job state and history
   - Provides pub/sub for task distribution
   - Persists data with AOF + RDB snapshots

2. **Asynq Client** - Task enqueueing
   - Creates tasks with payloads
   - Enqueues to specific queues (critical/default/low)
   - Sets retry policies and timeouts
   - Tracks task IDs for correlation

3. **Asynq Worker** - Task processing
   - Polls Redis for available tasks
   - Executes task handlers
   - Updates task status
   - Implements retry with exponential backoff

4. **Asynqmon** - Monitoring UI
   - Web-based dashboard on port 9084
   - Real-time queue metrics
   - Task inspection and management
   - Retry and delete operations
   - **Note**: Runs with x86_64 emulation on ARM64 (Apple Silicon) as no native ARM64 build is available

5. **SQLite Database** - Job persistence
   - `scrape_jobs` table for job tracking
   - Status: queued → processing → completed/failed
   - Error messages and retry counts
   - Links to result `requests` table

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Client creates scrape request                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              v
┌─────────────────────────────────────────────────────────────────┐
│ 2. Controller API Handler                                        │
│    - Creates ScrapeJob in database (status: queued)             │
│    - Enqueues task to Redis via Asynq Client                    │
│    - Returns job ID to client                                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              v
                      ┌───────────────┐
                      │ Redis (Asynq) │
                      │   - Task      │
                      │   - Metadata  │
                      └───────────────┘
                              │
                              v
┌─────────────────────────────────────────────────────────────────┐
│ 3. Asynq Worker (concurrent)                                     │
│    - Polls Redis for tasks                                       │
│    - Updates job status to "processing"                          │
│    - Executes handleScrapeTask                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              v
┌─────────────────────────────────────────────────────────────────┐
│ 4. Task Handler (processScrape)                                  │
│    - Score URL for quality                                       │
│    - Scrape content (calls scraper service)                      │
│    - Analyze text (calls textanalyzer service)                   │
│    - Save request to database                                    │
│    - Update job: status=completed, result_request_id=<id>        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              v (on error)
┌─────────────────────────────────────────────────────────────────┐
│ 5. Error Handling                                                │
│    - Update job: status=failed, error_message=<err>              │
│    - Increment retry counter                                     │
│    - Asynq schedules retry with exponential backoff              │
│      - Retry 1: 1 minute delay                                   │
│      - Retry 2: 5 minute delay                                   │
│      - Retry 3: 15 minute delay                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Configuration

### Environment Variables

```bash
# Redis connection
REDIS_ADDR=redis:6379           # Redis server address

# Worker settings
WORKER_CONCURRENCY=10           # Number of concurrent workers

# Task settings
LINK_SCORE_THRESHOLD=0.5        # Minimum URL quality score (0.0-1.0)
```

### Queue Priorities

Asynq supports multiple queues with priority weights:

```go
Queues: map[string]int{
    "critical": 6,   // High priority (6x weight)
    "default":  3,   // Normal priority (3x weight)
    "low":      1,   // Low priority (1x weight)
}
```

With `StrictPriority: false`, queues are processed proportionally based on weights, not strictly in order.

### Retry Policy

Tasks that fail are automatically retried with exponential backoff:

```go
RetryDelayFunc: func(n int, err error, task *asynq.Task) time.Duration {
    delays := []time.Duration{
        1 * time.Minute,   // First retry
        5 * time.Minute,   // Second retry
        15 * time.Minute,  // Third retry
    }
    // ...
}
```

Maximum 3 retries per task (configured via `asynq.MaxRetry(3)`).

### Task Timeout

Each task has a 10-minute execution timeout:

```go
asynq.Timeout(10 * time.Minute)
```

Tasks that exceed this timeout are automatically failed and subject to retry.

## Task Types

### TypeScrapeURL

Scrapes a URL, analyzes content, and stores the result.

**Payload:**
```json
{
  "job_id": "uuid-of-scrape-job",
  "url": "https://example.com/article",
  "extract_links": false
}
```

**Handler:** `handleScrapeTask` in `internal/queue/tasks.go`

**Flow:**
1. Parse task payload
2. Update job status to "processing"
3. Score URL for quality (skip threshold check for images)
4. If below threshold: create tombstoned record, mark job completed
5. If above threshold: scrape → analyze → save → link to job
6. If extract_links=true: extract and queue child links (max 10)

**Error Handling:**
- Updates job status to "failed" with error message
- Increments retry counter
- Returns error to Asynq for retry scheduling

## Database Schema

### scrape_jobs table

```sql
CREATE TABLE scrape_jobs (
    id TEXT PRIMARY KEY,                -- Job UUID
    url TEXT NOT NULL,                  -- URL to scrape
    extract_links INTEGER NOT NULL,     -- Boolean: extract child links
    status TEXT NOT NULL,               -- queued | processing | completed | failed
    retries INTEGER NOT NULL,           -- Retry attempt count
    created_at TIMESTAMP NOT NULL,      -- Creation time
    updated_at TIMESTAMP NOT NULL,      -- Last update time
    completed_at TIMESTAMP,             -- Completion time (nullable)
    error_message TEXT,                 -- Error details (nullable)
    result_request_id TEXT,             -- FK to requests.id (nullable)
    asynq_task_id TEXT,                 -- Asynq task ID for correlation
    FOREIGN KEY(result_request_id) REFERENCES requests(id) ON DELETE SET NULL
);
```

**Indexes:**
- `idx_scrape_jobs_status` - Filter by status
- `idx_scrape_jobs_created_at` - Order by creation time
- `idx_scrape_jobs_url` - Lookup by URL
- `idx_scrape_jobs_asynq_task_id` - Correlate with Asynq

## API Endpoints

### Create Scrape Request

```bash
POST /api/scrape-requests
Content-Type: application/json

{
  "url": "https://example.com/article",
  "extract_links": false
}
```

**Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "url": "https://example.com/article",
  "extract_links": false,
  "status": "queued",
  "retries": 0,
  "created_at": "2025-10-26T12:34:56Z",
  "updated_at": "2025-10-26T12:34:56Z",
  "asynq_task_id": "default:550e8400-e29b-41d4-a716-446655440000"
}
```

### List Scrape Requests

```bash
GET /api/scrape-requests?limit=50&offset=0
```

### Get Scrape Request

```bash
GET /api/scrape-requests/{job_id}
```

### Retry Failed Request

```bash
POST /api/scrape-requests/{job_id}/retry
```

### Delete Scrape Request

```bash
DELETE /api/scrape-requests/{job_id}
```

Note: This only deletes the job record. In-flight tasks will continue processing.

## Monitoring

### Asynqmon Dashboard

Access the monitoring UI at `http://localhost:9084` (in production: port 9084 on the server).

**Features:**
- Real-time queue statistics
- Active/pending/completed/failed task counts
- Task inspection and retry
- Queue management (pause/resume)
- Worker health status

### Metrics

Monitor these key metrics:

1. **Queue Depth** - Number of pending tasks
   - High depth may indicate worker saturation
   - Scale workers if consistently high

2. **Task Latency** - Time from enqueue to completion
   - Track P50, P95, P99 percentiles
   - High latency may indicate slow external services

3. **Failure Rate** - Percentage of failed tasks
   - Investigate if >5%
   - Check error messages in database

4. **Retry Rate** - Percentage of tasks requiring retries
   - Transient failures are normal
   - High retry rate may indicate service issues

5. **Worker Utilization** - Active/total workers ratio
   - Scale if consistently at 100%

### Logging

Worker logs task events with structured logging:

```json
{
  "level": "info",
  "msg": "processing scrape task",
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "url": "https://example.com/article",
  "extract_links": false
}
```

Error logs include full context:

```json
{
  "level": "error",
  "msg": "scrape task failed",
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "error": "failed to scrape: timeout"
}
```

## Operational Procedures

### Scaling Workers

Increase `WORKER_CONCURRENCY` environment variable:

```bash
# In docker-compose.yml
environment:
  - WORKER_CONCURRENCY=20  # Increase from 10
```

Or deploy additional controller instances (each runs independent workers).

### Pausing Queue Processing

Use Asynqmon UI to pause a queue:
1. Navigate to http://localhost:9084
2. Select queue (default/critical/low)
3. Click "Pause" button

Or use Asynq CLI:
```bash
asynq queue pause default
```

### Clearing Failed Tasks

Failed tasks remain in Redis history. To clear:
1. Use Asynqmon UI: Queue → Failed → Select All → Delete
2. Or use Asynq CLI:
   ```bash
   asynq task delete <task_id>
   ```

### Backup and Recovery

**Redis Persistence:**
- AOF (Append-Only File): `--appendonly yes`
- RDB Snapshots: `--save 60 1` (snapshot every 60s if ≥1 key changed)
- Backup files: `dump.rdb`, `appendonly.aof`

**Database Persistence:**
- `scrape_jobs` table in SQLite
- Regular database backups recommended

**Recovery:**
1. Restore Redis data files
2. Restore SQLite database
3. Restart controller service
4. Workers will resume processing queued tasks

### Troubleshooting

**Tasks stuck in "processing":**
- Check worker logs for errors
- Verify scraper/textanalyzer services are healthy
- Check task timeout (10 minutes)
- Investigate database connection issues

**High failure rate:**
- Check error messages in `scrape_jobs` table
- Verify external service availability
- Check network connectivity
- Review link score threshold settings

**Redis connection issues:**
- Verify Redis is running: `redis-cli ping`
- Check REDIS_ADDR environment variable
- Review Redis logs
- Verify network connectivity

**Worker not picking up tasks:**
- Check worker logs for startup errors
- Verify Redis connection
- Check queue configuration
- Restart controller service

## Future Enhancements

### Planned Features

1. **Text Analysis Queue**
   - Migrate text analysis from in-memory to Asynq
   - Separate queue for text-only processing
   - Remove `scraper_requests` package dependency

2. **Priority Queue Configuration**
   - Allow dynamic queue priority adjustment
   - Per-URL priority hints
   - User-defined priority rules

3. **Scheduled Tasks**
   - Periodic URL re-scraping
   - Content freshness checking
   - Integration with scheduler service

4. **Dead Letter Queue**
   - Archive permanently failed tasks
   - Separate storage for manual review
   - Automated failure analysis

5. **Advanced Monitoring**
   - Prometheus metrics export
   - Grafana dashboards
   - Alert rules for failures

6. **Queue Partitioning**
   - Per-domain queues to avoid rate limiting
   - Geo-distributed queue routing
   - Load balancing across regions

## References

- [Asynq Documentation](https://github.com/hibiken/asynq)
- [Redis Documentation](https://redis.io/documentation)
- [Controller README](../apps/controller/README.md)
- [Controller API Documentation](../apps/controller/API.md)
