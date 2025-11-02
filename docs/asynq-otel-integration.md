# Asynq OpenTelemetry Integration

## Overview

This document describes the OpenTelemetry integration implemented for Asynq task queues in DocuTab. The integration enables distributed tracing across async tasks and provides queue wait time metrics.

## Implementation Status

### ✅ Completed

1. **Task Payload Enhancements**
   - **Controller** (`apps/controller/internal/queue/client.go`)
     - Added `TraceID`, `SpanID`, and `EnqueuedAt` fields to task payloads
     - All task enqueue methods now capture trace context
     - Enqueue timestamp recorded for queue wait time calculation
   - **TextAnalyzer** (`apps/textanalyzer/internal/queue/client.go`)
     - Added trace context fields to all three task payload types
     - All enqueue methods capture and propagate trace context

2. **Trace Context Propagation**
   - Trace context extracted from current span when enqueuing tasks
   - Stored in task payload JSON for worker retrieval
   - Enables linking async task execution to originating request traces
   - Implemented across both Controller and TextAnalyzer services

3. **Worker Trace Context Extraction**
   - **Controller** (`apps/controller/internal/queue/tasks.go`)
     - Updated `handleScrapeTask` with trace context extraction and queue wait time
     - Updated `handleExtractLinksTask` with trace context extraction and queue wait time
   - **TextAnalyzer** (`apps/textanalyzer/internal/queue/tasks.go`)
     - Updated `handleProcessDocument` with trace context extraction and queue wait time
     - Updated `handleEnrichText` with trace context extraction and queue wait time
     - Updated `handleEnrichImage` with trace context extraction and queue wait time
   - All handlers create remote span contexts and link to originating traces
   - Queue wait times logged and recorded in trace spans

4. **Asynq Metrics in Prometheus**
   - Added Asynqmon scrape target to Prometheus configuration
   - Metrics available at `asynqmon:8080/metrics`
   - Includes queue size, task processing rates, retries, etc.

5. **Queues & Storage Dashboard**
   - Created comprehensive dashboard at `config/grafana/provisioning/dashboards/docutab-queues-storage.json`
   - Monitors queue sizes, processing rates, wait times
   - Database connection pools, query latency, storage growth
   - Queue-related logs integration

6. **Unified Observability Dashboard**
   - Created coordinated dashboard at `config/grafana/provisioning/dashboards/docutab-observability.json`
   - Combines traces, metrics, and logs in a single view
   - Shows Asynq queue metrics alongside service metrics

7. **Web Frontend Tracing** (`apps/web`)
   - Installed OpenTelemetry Web SDK packages
   - Created tracing initialization module (`src/utils/tracing.js`)
   - Auto-instrumentation for fetch API and document load events
   - Custom spans for key user operations (scrape requests, text analysis)
   - Trace context propagation via W3C headers to backend services
   - OTLP exporter configured to send traces to Tempo
   - Vite dev server proxy for CORS-free trace export in development
   - Full end-to-end tracing: Browser → HTTP Request → Backend API → Queue Task → Worker

### 🔨 Optional Future Enhancements

The core implementation is complete. These are optional enhancements for the future:

1. **Automatic trace context propagation** using Asynq middleware
2. **Custom Prometheus metrics** for app-specific queue metrics beyond Asynqmon
3. **Dead letter queue** monitoring and alerting
4. **Queue autoscaling** based on wait time thresholds
5. **Task-level tracing spans** for each sub-operation within tasks

### Benefits

1. **Distributed Tracing**
   - End-to-end trace visibility from HTTP request → task enqueue → task processing
   - Trace IDs link all async operations to originating request
   - Helps debug complex multi-service workflows

2. **Queue Performance Monitoring**
   - Queue wait time metrics enable queue depth/backlog analysis
   - Identify bottlenecks and scaling needs
   - Track p50/p95/p99 wait times across queues

3. **Operational Visibility**
   - Unified dashboard for queue health
   - Database performance correlation with queue activity
   - Storage growth tracking

## Dashboard Panels

### Queues Section
- **Queue Size by State**: pending, active, retry tasks
- **Task Processing Rate**: completed vs failed rates
- **Queue Wait Time**: p50/p95/p99 latency before processing
- **Tasks in Retry State**: gauge showing retry backlog

### Database Section
- **Database Connections**: open vs idle connections
- **Database Query Latency**: p95/p99 query times
- **PostgreSQL Database Size**: growth over time
- **Top 10 Tables by Size**: storage breakdown

### Logs Section
- **Queue-Related Logs**: filtered for queue/task/job events

## Metrics Available

From Asynqmon Prometheus endpoint:
```
# Queue metrics
asynq_queue_size{queue="scrape", state="pending"}
asynq_queue_size{queue="scrape", state="active"}
asynq_queue_size{queue="scrape", state="retry"}

# Task processing
asynq_tasks_processed_total{queue="scrape", status="completed"}
asynq_tasks_processed_total{queue="scrape", status="failed"}

# Wait time (requires custom instrumentation in worker)
asynq_task_wait_duration_seconds_bucket{queue="scrape", le="1.0"}
asynq_task_wait_duration_seconds_bucket{queue="scrape", le="5.0"}
asynq_task_wait_duration_seconds_bucket{queue="scrape", le="30.0"}
```

## Testing the Integration

### Backend Tracing
1. **Restart services** to pick up the updated task payloads
2. **Enqueue a task** through the API
3. **Check Tempo** for distributed traces showing the full request → task chain
4. **View Grafana** dashboard "DocuTab Queues & Storage" for metrics
5. **Examine logs** to see queue wait times logged per task

### Web Frontend Tracing
1. **Start the web development server**: `cd apps/web && npm run dev`
2. **Open browser console** to see tracing initialization log
3. **Perform a scrape request** or text analysis from the UI
4. **Check Tempo** in Grafana to see end-to-end traces:
   - Browser span for user action (e.g., `user.create_scrape_request`)
   - HTTP fetch span from browser to controller
   - Controller HTTP handler span
   - Queue enqueue span
   - Queue task processing span with remote link to originating trace
5. **Verify trace context propagation**:
   - All spans should share the same `TraceID`
   - Queue task spans should have the enqueue span as parent
   - Browser → Backend → Queue spans should form a complete trace tree

### Trace Verification
Check that traces include:
- **Service name**: `docutab-web`, `controller`, `textanalyzer`
- **Span attributes**: URL, job IDs, analysis IDs, queue wait times
- **Remote span links**: Queue workers link back to enqueue spans
- **HTTP headers**: `traceparent` header propagated from browser to backend

## Related Files

### Backend Services
- `apps/controller/internal/queue/client.go` - Task enqueuing with trace context
- `apps/controller/internal/queue/tasks.go` - Worker task processing with trace extraction
- `apps/controller/internal/queue/trace_test.go` - Tests for trace context propagation
- `apps/textanalyzer/internal/queue/client.go` - TextAnalyzer task enqueuing with trace context
- `apps/textanalyzer/internal/queue/tasks.go` - TextAnalyzer worker with trace extraction
- `apps/textanalyzer/internal/queue/trace_test.go` - Tests for trace context propagation

### Web Frontend
- `apps/web/src/utils/tracing.js` - OpenTelemetry Web SDK initialization and utilities
- `apps/web/src/services/api.js` - API service with custom trace spans
- `apps/web/src/main.jsx` - App entry point with tracing initialization
- `apps/web/vite.config.js` - Vite proxy configuration for OTLP endpoint
- `apps/web/.env.example` - Environment variable configuration

### Configuration & Dashboards
- `config/prometheus/prometheus.yml` - Asynqmon scrape configuration
- `config/tempo-config.yaml` - Tempo OTLP receiver configuration
- `config/grafana/provisioning/dashboards/docutab-queues-storage.json` - Dashboard
- `config/grafana/provisioning/dashboards/docutab-observability.json` - Unified observability
