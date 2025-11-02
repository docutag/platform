# Logging Setup

PurpleTab uses structured logging with JSON output from all Go services, aggregated by Loki and visualized in Grafana.

## Architecture

- **Structured Logging**: All Go services use Go's built-in `slog` library with JSON output
- **Log Aggregation**: Loki collects logs from all Docker containers
- **Visualization**: Grafana provides dashboards and log exploration
- **Docker Integration**: Docker Loki logging driver sends container logs to Loki

## Quick Start

### 1. Install Docker Loki Logging Driver

Before starting the services, install the Loki Docker logging plugin:

```bash
docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions
```

Verify installation:

```bash
docker plugin ls
```

### 2. Start Services

```bash
docker-compose up -d
```

This will start:
- All PurpleTab services (controller, scraper, textanalyzer, scheduler, web)
- Loki (log aggregation) on port 3100
- Grafana (dashboards) on port 3000

### 3. Access Grafana

Open http://localhost:3000 in your browser.

**No authentication required** - the dev instance has anonymous access enabled with Admin role.

## Features

### Structured Logging

All Go services now emit structured JSON logs with consistent fields:

```json
{
  "time": "2025-10-24T10:30:45.123Z",
  "level": "INFO",
  "msg": "controller service starting",
  "port": 8080,
  "database": "/app/data/controller.db",
  "scraper_url": "http://scraper:8080"
}
```

Log levels:
- `INFO`: Normal operations
- `WARN`: Warning conditions
- `ERROR`: Error conditions requiring attention

### Grafana Dashboard

A pre-configured dashboard is available at: **PurpleTab Service Logs**

Panels include:
1. **All Service Logs** - Combined view of all service logs
2. **Controller Errors** - Error logs from controller service
3. **Scraper Errors** - Error logs from scraper service
4. **TextAnalyzer Errors** - Error logs from textanalyzer service
5. **Scheduler Errors** - Error logs from scheduler service
6. **Error Rate by Service** - Time series graph of error rates

### Loki Configuration

Loki is configured with:
- **Retention**: 31 days (744 hours)
- **Storage**: Local filesystem (`/loki` volume)
- **Schema**: TSDB with filesystem object store
- **Query range**: 30 days max

Configuration file: `config/loki-config.yaml`

## Usage

### Querying Logs

In Grafana's Explore view, you can use LogQL queries:

**All logs from a service:**
```logql
{container_name="docutag-controller"}
```

**Error logs only:**
```logql
{container_name="docutag-controller"} | json | level="ERROR"
```

**Logs containing specific text:**
```logql
{container_name=~"docutag.*"} |= "database"
```

**Logs from all services:**
```logql
{container_name=~"docutag.*"}
```

**Count errors in last 5 minutes:**
```logql
sum(count_over_time({container_name=~"docutag.*"} | json | level="ERROR" [5m]))
```

### Service Labels

Each service has automatic labels:
- `container_name`: The Docker container name (e.g., `docutag-controller`)
- `compose_project`: The Docker Compose project name
- `compose_service`: The service name from docker-compose.yml

### JSON Field Extraction

All structured fields from JSON logs are automatically extracted:

```logql
{container_name="docutag-scraper"} | json | port="8080"
```

Common fields:
- `msg`: Log message
- `level`: Log level (INFO, WARN, ERROR)
- `time`: Timestamp
- `error`: Error details (when present)
- Service-specific fields (port, database, urls, etc.)

## Configuration Files

### Loki
- **Config**: `config/loki-config.yaml`
- **Data**: Docker volume `loki-data`

### Grafana
- **Datasource**: `config/grafana/provisioning/datasources/loki.yaml`
- **Dashboard**: `config/grafana/provisioning/dashboards/docutag-logs.json`
- **Data**: Docker volume `grafana-data`

## Troubleshooting

### Logs not appearing in Grafana

1. Check Loki is running:
   ```bash
   docker logs docutag-loki
   ```

2. Verify Loki plugin is installed:
   ```bash
   docker plugin ls
   ```

3. Check service logs are being sent:
   ```bash
   docker inspect docutag-controller | grep -A 10 "LogConfig"
   ```

### Plugin installation fails

If you get permission errors, you may need to use `sudo`:

```bash
sudo docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions
```

### Grafana datasource not connecting

Check that Loki is accessible from Grafana:

```bash
docker exec docutag-grafana wget -O- http://loki:3100/ready
```

### Too many logs / disk space

Adjust retention in `config/loki-config.yaml`:

```yaml
limits_config:
  retention_period: 168h  # 7 days instead of 31
```

Then restart Loki:

```bash
docker-compose restart loki
```

## Development

### Changing Log Level

To enable debug logging, modify the service's main.go:

```go
logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    Level: slog.LevelDebug,  // Changed from LevelInfo
}))
```

### Adding Custom Fields

Add structured fields to any log statement:

```go
logger.Info("processing request",
    "user_id", userID,
    "request_id", requestID,
    "duration_ms", duration.Milliseconds(),
)
```

### Disabling Loki Driver (for local dev)

Comment out the `logging:` section in `docker-compose.yml` for a service to use default Docker logging:

```yaml
# logging:
#   driver: loki
#   options:
#     loki-url: "http://localhost:3100/loki/api/v1/push"
```

## Production Considerations

This is a **development setup** with:
- ❌ No authentication
- ❌ No TLS/HTTPS
- ❌ Limited retention (31 days)
- ❌ Single-node Loki
- ❌ Local filesystem storage

For production:
1. Enable Grafana authentication
2. Use distributed Loki with object storage (S3, GCS)
3. Add TLS certificates
4. Configure alerting
5. Set up log retention policies
6. Use a reverse proxy (nginx, traefik)
7. Implement log sampling for high-volume services

## References

- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/logql/)
- [Docker Loki Driver](https://grafana.com/docs/loki/latest/clients/docker-driver/)
- [Go slog Package](https://pkg.go.dev/log/slog)
