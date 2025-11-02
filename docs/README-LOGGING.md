# PurpleTab Structured Logging & Observability

This document provides a quick overview of the structured logging and observability setup.

## What Was Implemented

### 1. **Structured Logging** ✅
All Go services now use `log/slog` with JSON output for structured logging:
- **Controller** - apps/controller/cmd/controller/main.go:39
- **Scraper** - apps/scraper/cmd/api/main.go:29
- **TextAnalyzer** - apps/textanalyzer/cmd/server/main.go:21
- **Scheduler** - apps/scheduler/cmd/api/main.go:28

Example log format:
```json
{
  "time": "2025-10-24T20:48:54.619Z",
  "level": "INFO",
  "msg": "controller service starting",
  "port": 8080,
  "scraper_url": "http://scraper:8080",
  "textanalyzer_url": "http://textanalyzer:8080",
  "database": "/app/data/controller.db"
}
```

### 2. **Log Aggregation with Loki** ✅
- **Service**: Loki 3.0.0 running on port 3100
- **Configuration**: config/loki-config.yaml
- **Storage**: Local filesystem with 31-day retention
- **Docker Integration**: All services use Loki Docker logging driver

### 3. **Visualization with Grafana** ✅
- **Service**: Grafana 11.0.0 on port 3000
- **Authentication**: Disabled (dev mode) - anonymous access with Admin role
- **Datasource**: Auto-provisioned Loki connection
- **Dashboard**: Pre-configured "PurpleTab Service Logs" dashboard

## Quick Start

### First Time Setup

```bash
# 1. Install Docker Loki logging plugin
./scripts/setup-logging.sh

# 2. Build and start services
docker-compose build
docker-compose up -d

# 3. Wait for services to be healthy (~30-60 seconds)
docker-compose ps

# 4. Verify logging is working
./scripts/test-loki.sh
```

### Accessing Grafana

Open http://localhost:3000 in your browser. No login required!

The "PurpleTab Service Logs" dashboard shows:
- All service logs (combined view)
- Error logs per service (4 panels)
- Error rate timeline graph

## Usage Examples

### Exploring Logs in Grafana

1. **Go to Explore** (compass icon in sidebar)
2. **Run LogQL queries**:

```logql
# All logs from controller
{container_name="docutag-controller"}

# Only errors
{container_name="docutag-controller"} | json | level="ERROR"

# Errors from all services
{container_name=~"docutag.*"} | json | level="ERROR"

# Search for specific text
{container_name=~"docutag.*"} |= "database"

# Count errors in last 5 minutes
sum(count_over_time({container_name=~"docutag.*"} | json | level="ERROR" [5m]))
```

### Checking Logs via CLI

```bash
# View structured logs from any service
docker logs docutag-controller --tail 20

# Follow logs in real-time
docker logs -f docutag-scraper

# Query Loki directly
curl -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={container_name="docutag-controller"}' \
  --data-urlencode 'limit=10'
```

## Architecture

```
┌─────────────────────────────────────────────┐
│                                             │
│  Go Services (JSON structured logs)        │
│  ┌──────────┐ ┌─────────┐ ┌──────────┐    │
│  │Controller│ │ Scraper │ │TextAnalyz│    │
│  └────┬─────┘ └────┬────┘ └────┬─────┘    │
│       │            │            │           │
│       └────────────┴────────────┘           │
│                    │                        │
└────────────────────┼────────────────────────┘
                     │
         Docker Loki Logging Driver
                     │
                     ▼
            ┌──────────────┐
            │              │
            │  Loki :3100  │
            │              │
            │ (Aggregates  │
            │  & Indexes)  │
            └──────┬───────┘
                   │
                   │ LogQL queries
                   │
                   ▼
            ┌──────────────┐
            │              │
            │Grafana :3000 │
            │              │
            │ (Dashboards  │
            │   & Explore) │
            └──────────────┘
```

## Files Added/Modified

### New Files
- `config/loki-config.yaml` - Loki configuration
- `config/grafana/provisioning/datasources/loki.yaml` - Grafana datasource
- `config/grafana/provisioning/dashboards/dashboards.yaml` - Dashboard config
- `config/grafana/provisioning/dashboards/docutag-logs.json` - Logs dashboard
- `scripts/setup-logging.sh` - Setup script
- `scripts/test-loki.sh` - Test script
- `docs/LOGGING.md` - Detailed documentation

### Modified Files
- `docker-compose.yml` - Added Loki, Grafana, and logging drivers
- `apps/controller/cmd/controller/main.go` - Structured logging
- `apps/scraper/cmd/api/main.go` - Structured logging
- `apps/textanalyzer/cmd/server/main.go` - Structured logging
- `apps/scheduler/cmd/api/main.go` - Structured logging

## Key Features

✅ **Structured JSON Logging** - All Go services emit structured logs
✅ **Automatic Collection** - Docker Loki driver sends logs automatically
✅ **Centralized Storage** - All logs in one place (Loki)
✅ **Powerful Queries** - LogQL for filtering and aggregation
✅ **Visual Dashboards** - Pre-built dashboard for common queries
✅ **No Auth (Dev Mode)** - Easy access for development
✅ **31-Day Retention** - Configurable log retention

## Troubleshooting

### Logs not appearing in Grafana?

```bash
# Check if Loki is running
docker logs docutag-loki --tail 50

# Verify plugin is installed
docker plugin ls | grep loki

# Test Loki directly
curl http://localhost:3100/ready

# Check service logs format
docker logs docutag-controller --tail 5
```

### Grafana can't connect to Loki?

```bash
# Test from Grafana container
docker exec docutag-grafana wget -O- http://loki:3100/ready

# Restart services
docker-compose restart grafana loki
```

## Next Steps

For more detailed information, see:
- **Full Documentation**: docs/LOGGING.md
- **Loki Docs**: https://grafana.com/docs/loki/latest/
- **LogQL Guide**: https://grafana.com/docs/loki/latest/logql/

## Production Notes

⚠️ This is a **development setup**. For production:
1. Enable Grafana authentication
2. Use distributed Loki with object storage (S3/GCS)
3. Add TLS/HTTPS
4. Configure alerting
5. Implement log sampling for high-volume services
6. Use a reverse proxy

See docs/LOGGING.md for production recommendations.
