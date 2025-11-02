# Distributed Tracing with Grafana Tempo

PurpleTab implements distributed tracing using OpenTelemetry and Grafana Tempo to provide end-to-end visibility into request flows across all microservices.

## Overview

Distributed tracing allows you to track requests as they flow through the system, from the initial HTTP request to the controller, through scraper and text analyzer services, and back. This is invaluable for:

- **Performance optimization**: Identify slow operations and bottlenecks
- **Debugging**: Understand request flow and pinpoint failures
- **Service dependencies**: Visualize how services interact
- **Monitoring**: Track service health and latency

## Architecture

### Components

1. **Grafana Tempo** - Distributed tracing backend
   - Receives traces via OTLP (OpenTelemetry Protocol)
   - Stores traces locally with 7-day retention
   - Provides search and query capabilities
   - Ports:
     - `3200` - HTTP API and UI
     - `4317` - OTLP gRPC
     - `4318` - OTLP HTTP

2. **Shared Tracing Package** (`pkg/tracing`)
   - Provides reusable tracing functionality for all Go services
   - Handles tracer initialization
   - Provides HTTP middleware for automatic request instrumentation
   - Exports helper functions for custom instrumentation

3. **Instrumented Services**
   - Controller (`docutag-controller`)
   - Scraper (`docutag-scraper`)
   - TextAnalyzer (`docutag-textanalyzer`)
   - Scheduler (`docutag-scheduler`)

### Trace Flow

```
User Request → Controller (creates trace)
                    ↓
              Scraper Service (child span)
                    ↓
              TextAnalyzer Service (child span)
                    ↓
              All spans → Tempo (via OTLP gRPC)
```

## Configuration

### Environment Variables

All Go services support the following tracing environment variable:

- `TEMPO_ENDPOINT` - Tempo OTLP gRPC endpoint (default: `tempo:4317`)

Example in `docker-compose.yml`:
```yaml
environment:
  - TEMPO_ENDPOINT=tempo:4317
```

### Tempo Configuration

Tempo configuration is in `config/tempo-config.yaml`:

```yaml
storage:
  trace:
    backend: local
    wal:
      path: /var/tempo/wal
    local:
      path: /var/tempo/blocks

compactor:
  compaction:
    block_retention: 168h  # 7 days
```

### Grafana Integration

Tempo is configured as a data source in Grafana with:
- UID: `tempo`
- Trace-to-log correlation with Loki
- Service map and node graph enabled

Configuration file: `config/grafana/provisioning/datasources/tempo.yaml`

## Usage

### Viewing Traces in Grafana

1. **Open Grafana**: http://localhost:3000
2. **Navigate to Explore** (compass icon in left sidebar)
3. **Select Tempo** as the data source
4. **Search for traces** by:
   - Service name (e.g., `docutag-controller`)
   - Operation name (e.g., `POST /api/scrape`)
   - Duration (e.g., traces > 1s)
   - Tags and attributes

### Trace-to-Log Correlation

Traces are automatically correlated with logs:

1. **From a trace**: Click on any span to see "Logs for this span" link
2. **From logs**: Look for `trace_id` field in structured logs, click to view trace

### Service Map

The service map visualizes dependencies between services:

1. In Grafana, go to **Explore**
2. Select **Tempo** as data source
3. Click **Service Graph** tab
4. View service dependencies and request rates

## Implementation Details

### Shared Tracing Package

Location: `pkg/tracing/`

#### Core Functions

**`InitTracer(serviceName string)`**
Initializes OpenTelemetry tracer for a service:
```go
tp, err := tracing.InitTracer("docutag-controller")
if err != nil {
    logger.Warn("failed to initialize tracer", "error", err)
} else {
    defer tp.Shutdown(context.Background())
}
```

**`HTTPMiddleware(serviceName string)`**
Wraps HTTP handlers with automatic tracing:
```go
handler := tracing.HTTPMiddleware("controller")(corsMiddleware(mux))
server := &http.Server{
    Addr:    ":8080",
    Handler: handler,
}
```

This automatically creates spans for all HTTP requests with:
- Operation name: `METHOD /path` (e.g., `POST /api/scrape`)
- HTTP attributes (method, status code, URL)
- Request duration
- Error status if applicable

#### Helper Functions

**`AddSpanAttributes(r *http.Request, attrs ...attribute.KeyValue)`**
Add custom attributes to current span:
```go
tracing.AddSpanAttributes(r,
    attribute.String("user_id", userId),
    attribute.Int("items_count", count),
)
```

**`AddSpanEvent(r *http.Request, name string, attrs ...attribute.KeyValue)`**
Add events to track specific occurrences:
```go
tracing.AddSpanEvent(r, "cache_miss",
    attribute.String("key", cacheKey),
)
```

**`LogWithTrace(r *http.Request, logger *slog.Logger, level, msg, ...args)`**
Log with trace context for correlation:
```go
tracing.LogWithTrace(r, logger, slog.LevelInfo, "processing request",
    "url", url,
)
```

### Service Instrumentation

Each Go service is instrumented as follows:

1. **Initialize tracer** at startup (in `main()`)
2. **Wrap HTTP handler** with `HTTPMiddleware`
3. **Gracefully shutdown** tracer on exit

Example from `apps/controller/cmd/controller/main.go`:
```go
// Initialize tracing
tp, err := tracing.InitTracer("docutag-controller")
if err != nil {
    logger.Warn("failed to initialize tracer, continuing without tracing", "error", err)
} else {
    defer func() {
        if err := tp.Shutdown(context.Background()); err != nil {
            logger.Error("error shutting down tracer", "error", err)
        }
    }()
    logger.Info("tracing initialized successfully")
}

// ... setup routes in mux ...

// Wrap with tracing middleware
httpHandler := tracing.HTTPMiddleware("controller")(corsMiddleware(mux))

server := &http.Server{
    Addr:    addr,
    Handler: httpHandler,
}
```

### Trace Context Propagation

Trace context is automatically propagated between services using W3C Trace Context:

1. **Outgoing requests**: HTTP client automatically injects trace headers
2. **Incoming requests**: HTTP middleware extracts trace context
3. **Child spans**: Created automatically for downstream service calls

This creates a complete trace showing the full request path across all services.

## Monitoring and Operations

### Checking Tracing Status

**View service logs** for tracing initialization:
```bash
docker-compose logs controller | grep tracing
```

Expected output:
```json
{"level":"INFO","msg":"initializing tracer","service":"docutag-controller","tempo_endpoint":"tempo:4317"}
{"level":"INFO","msg":"tracer initialized successfully","service":"docutag-controller"}
{"level":"INFO","msg":"tracing initialized successfully"}
```

**Check Tempo health**:
```bash
curl http://localhost:3200/ready
```

**View Tempo metrics**:
```bash
curl http://localhost:3200/metrics
```

### Troubleshooting

#### No Traces Appearing

1. **Check Tempo is running**:
   ```bash
   docker-compose ps tempo
   ```

2. **Verify services can connect to Tempo**:
   ```bash
   docker-compose logs <service> | grep -E "(trace|tempo)"
   ```

3. **Check for export errors**:
   ```bash
   docker-compose logs <service> | grep "export"
   ```

4. **Ensure TEMPO_ENDPOINT is set**:
   ```bash
   docker exec docutag-controller env | grep TEMPO
   ```

#### Trace Export Errors

If you see "connection refused" or "no such host":
- Services may have started before Tempo was ready
- Restart services: `docker-compose restart controller scraper textanalyzer scheduler`

#### Traces Not Correlating with Logs

Ensure structured logging includes trace_id:
```go
tracing.LogWithTrace(r, logger, slog.LevelInfo, "message", "key", "value")
```

## Performance Considerations

### Sampling

Currently configured to sample **all traces** (`AlwaysSample`):
```go
sdktrace.WithSampler(sdktrace.AlwaysSample())
```

For production, consider probability sampling:
```go
sdktrace.WithSampler(sdktrace.TraceIDRatioBased(0.1))  // Sample 10% of traces
```

### Batching

Traces are batched before export to reduce overhead:
```go
sdktrace.WithBatcher(exporter)
```

Default batch configuration:
- Max queue size: 2048 spans
- Max export batch size: 512 spans
- Batch timeout: 5 seconds

### Storage

Tempo uses local storage with:
- **Block retention**: 7 days (configurable in `tempo-config.yaml`)
- **Storage path**: `/var/tempo` (Docker volume)

Monitor storage usage:
```bash
docker exec docutag-tempo du -sh /var/tempo
```

## Best Practices

### 1. Use Semantic Naming

Operation names should be semantic and consistent:
```go
// Good
tracing.HTTPMiddleware("controller")  // Creates spans like "POST /api/scrape"

// Avoid generic names
tracing.HTTPMiddleware("service")
```

### 2. Add Business Context

Add attributes that help with debugging:
```go
tracing.AddSpanAttributes(r,
    attribute.String("url", targetURL),
    attribute.String("request_id", reqID),
    attribute.Int("retry_count", retries),
)
```

### 3. Record Important Events

Use events for significant occurrences:
```go
tracing.AddSpanEvent(r, "scraping_started",
    attribute.String("url", url))

tracing.AddSpanEvent(r, "ai_analysis_complete",
    attribute.Int("token_count", tokens))
```

### 4. Handle Errors Properly

Set span status on errors:
```go
span := trace.SpanFromContext(r.Context())
if err != nil {
    span.RecordError(err)
    span.SetStatus(codes.Error, err.Error())
}
```

### 5. Correlate with Logs

Always use structured logging with trace context:
```go
tracing.LogWithTrace(r, logger, slog.LevelWarn, "slow operation detected",
    "duration_ms", duration.Milliseconds())
```

## Future Enhancements

Potential improvements for the tracing implementation:

1. **Metrics Generation**: Enable Prometheus metrics generation from traces
2. **Sampling Strategies**: Implement adaptive sampling for production
3. **Trace Analysis**: Add dashboards for latency percentiles and error rates
4. **Alerting**: Set up alerts for high latency or error traces
5. **Remote Storage**: Consider object storage backend for long-term retention

## References

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [W3C Trace Context Specification](https://www.w3.org/TR/trace-context/)
- [PurpleTab Logging Documentation](./LOGGING.md)
