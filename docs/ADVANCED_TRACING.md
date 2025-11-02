# Advanced Tracing - Custom Instrumentation

This guide shows how to add detailed custom instrumentation to your services for richer trace data.

## Overview

The basic HTTP middleware provides automatic request/response tracing, but custom instrumentation adds:

- **Custom child spans** for specific operations
- **Span attributes** with contextual data
- **Span events** marking important milestones
- **Error recording** with structured details
- **Performance metrics** (duration, counts, sizes)

## Enhanced Tracing Functions

The `pkg/tracing` package provides helper functions for custom instrumentation:

### StartSpan
Create a custom child span for specific operations:

```go
ctx, span := tracing.StartSpan(r.Context(), "operation_name")
defer span.End()

// Do work...
```

### SetSpanAttributes
Add contextual data to spans:

```go
tracing.SetSpanAttributes(ctx,
    attribute.String("url", targetURL),
    attribute.Int("items_count", count),
    attribute.Bool("cached", isCached))
```

### AddEvent
Mark important events within a span:

```go
tracing.AddEvent(ctx, "cache_hit",
    attribute.String("cache_key", key))
```

### RecordError
Record errors with proper status:

```go
if err != nil {
    tracing.RecordError(ctx, err)
    span.End()
    return err
}
```

## Example: Scraper Service Instrumentation

The scraper's `handleScrape` function demonstrates comprehensive instrumentation:

### 1. Add Attributes to Parent Span

```go
// Add request details to the HTTP span
tracing.SetSpanAttributes(r.Context(),
    attribute.String("scrape.url", req.URL),
    attribute.Bool("scrape.force", req.Force))
```

This adds attributes to the HTTP request span created by the middleware.

### 2. Database Check Span

```go
ctx, span := tracing.StartSpan(r.Context(), "database.check_existing")
span.SetAttributes(attribute.String("db.url", req.URL))

existing, err := s.db.GetByURL(req.URL)
if err != nil {
    tracing.RecordError(ctx, err)
    span.End()
    return
}

if existing != nil {
    // Cache hit - record event
    tracing.AddEvent(ctx, "cache_hit",
        attribute.String("cached_id", existing.ID))
    span.SetAttributes(
        attribute.Bool("db.found", true),
        attribute.String("db.uuid", existing.ID))
    span.End()
    return
}

span.SetAttributes(attribute.Bool("db.found", false))
span.End()
```

**What this shows in Tempo:**
- Child span "database.check_existing"
- Attributes: `db.url`, `db.found`, `db.uuid`
- Event: "cache_hit" (if cached)
- Duration of database operation
- Error details (if query failed)

### 3. Scraping Operation Span

```go
ctx, scrapeSpan := tracing.StartSpan(ctx, "scraper.scrape")
scrapeSpan.SetAttributes(
    attribute.String("scrape.url", req.URL),
    attribute.String("scrape.timeout", "10m"))

result, err := s.scraper.Scrape(ctx, req.URL)
if err != nil {
    tracing.RecordError(ctx, err)
    scrapeSpan.End()
    return
}

// Add result metrics
scrapeSpan.SetAttributes(
    attribute.String("scrape.uuid", result.ID),
    attribute.Int("scrape.links_count", len(result.Links)),
    attribute.Int("scrape.images_count", len(result.Images)),
    attribute.String("scrape.title", result.Title))
scrapeSpan.End()
```

**What this shows in Tempo:**
- Child span "scraper.scrape" (may take several seconds)
- Attributes: URLs, timeouts, result counts
- Success/failure status
- Actual scraping duration

### 4. Database Save Span

```go
ctx, saveSpan := tracing.StartSpan(r.Context(), "database.save")
saveSpan.SetAttributes(
    attribute.String("db.uuid", result.ID),
    attribute.Int("db.links", len(result.Links)),
    attribute.Int("db.images", len(result.Images)))

if err := s.db.SaveScrapedData(result); err != nil {
    tracing.RecordError(ctx, err)
} else {
    tracing.AddEvent(ctx, "data_saved",
        attribute.String("uuid", result.ID))
}
saveSpan.End()
```

**What this shows in Tempo:**
- Child span "database.save"
- Attributes: data being saved
- Event: "data_saved" on success
- Save duration
- Error details on failure

## Viewing Enhanced Traces in Grafana

### Access Tempo in Grafana

1. Open Grafana: http://localhost:3000
2. Go to **Explore** (compass icon)
3. Select **Tempo** as datasource
4. Search for traces

### Understanding the Trace View

A single scrape request now shows:

```
POST /api/scrape (parent span - from HTTP middleware)
├── database.check_existing (database query)
│   └── Event: cache_hit (if cached)
├── scraper.scrape (actual web scraping)
│   └── Attributes: url, links_count, images_count, title
└── database.save (persist results)
    └── Event: data_saved
```

### Viewing Span Details

Click on any span to see:

- **Duration**: How long the operation took
- **Attributes**: All contextual data
  - `scrape.url`: Target URL
  - `scrape.links_count`: Number of links found
  - `db.found`: Whether cached data existed
- **Events**: Milestones within the span
  - `cache_hit`: When cached data was used
  - `data_saved`: When data was persisted
- **Status**: Success or error
- **Error details**: If the operation failed

### Filtering by Attributes

Search for specific scenarios:

```
# All scrapes that were cached
{db.found=true}

# Scrapes with many links
{scrape.links_count>100}

# Failed scrapes
{status.code=ERROR}

# Specific URL
{scrape.url="https://example.com"}
```

## Common Instrumentation Patterns

### Pattern 1: Database Operations

```go
ctx, span := tracing.StartSpan(ctx, "database.query")
span.SetAttributes(
    attribute.String("db.operation", "SELECT"),
    attribute.String("db.table", "requests"))

results, err := db.Query(ctx, query)
if err != nil {
    tracing.RecordError(ctx, err)
    span.End()
    return err
}

span.SetAttributes(attribute.Int("db.rows_returned", len(results)))
span.End()
```

### Pattern 2: HTTP Client Calls

```go
ctx, span := tracing.StartSpan(ctx, "http.client.call")
span.SetAttributes(
    attribute.String("http.method", "POST"),
    attribute.String("http.url", targetURL))

resp, err := httpClient.Do(req.WithContext(ctx))
if err != nil {
    tracing.RecordError(ctx, err)
    span.End()
    return err
}

span.SetAttributes(
    attribute.Int("http.status_code", resp.StatusCode),
    attribute.Int64("http.response_size", resp.ContentLength))
span.End()
```

### Pattern 3: AI/ML Operations

```go
ctx, span := tracing.StartSpan(ctx, "ai.analysis")
span.SetAttributes(
    attribute.String("ai.model", "llama3"),
    attribute.Int("ai.input_tokens", len(input)))

result, err := aiClient.Analyze(ctx, input)
if err != nil {
    tracing.RecordError(ctx, err)
    span.End()
    return err
}

span.SetAttributes(
    attribute.Int("ai.output_tokens", len(result)),
    attribute.Float64("ai.confidence", result.Confidence))
tracing.AddEvent(ctx, "analysis_complete")
span.End()
```

### Pattern 4: Cache Operations

```go
ctx, span := tracing.StartSpan(ctx, "cache.get")
span.SetAttributes(attribute.String("cache.key", key))

value, found := cache.Get(key)
if found {
    tracing.AddEvent(ctx, "cache_hit")
    span.SetAttributes(attribute.Bool("cache.hit", true))
} else {
    tracing.AddEvent(ctx, "cache_miss")
    span.SetAttributes(attribute.Bool("cache.hit", false))
}
span.End()
```

### Pattern 5: Batch Processing

```go
ctx, span := tracing.StartSpan(ctx, "batch.process")
span.SetAttributes(attribute.Int("batch.size", len(items)))

processed := 0
failed := 0

for i, item := range items {
    // Create span for each item
    itemCtx, itemSpan := tracing.StartSpan(ctx, "batch.process_item")
    itemSpan.SetAttributes(
        attribute.Int("batch.index", i),
        attribute.String("item.id", item.ID))

    if err := processItem(itemCtx, item); err != nil {
        tracing.RecordError(itemCtx, err)
        failed++
    } else {
        processed++
    }
    itemSpan.End()
}

span.SetAttributes(
    attribute.Int("batch.processed", processed),
    attribute.Int("batch.failed", failed))
span.End()
```

## Naming Conventions

### Span Names

Use hierarchical naming with dots for grouping:

```
service.operation
database.query
http.client.request
ai.analyze
cache.get
```

### Attribute Keys

Follow semantic conventions where possible:

**HTTP attributes:**
- `http.method` - Request method
- `http.url` - Target URL
- `http.status_code` - Response status

**Database attributes:**
- `db.system` - Database type (sqlite, postgres)
- `db.operation` - SQL operation (SELECT, INSERT)
- `db.table` - Table name

**Custom attributes:**
- `scrape.url` - URL being scraped
- `scrape.links_count` - Number of links found
- `ai.model` - AI model used
- `cache.hit` - Whether cache was hit

### Event Names

Use snake_case for events:

```
cache_hit
cache_miss
data_saved
analysis_complete
retry_attempt
rate_limit_hit
```

## Performance Considerations

### Span Overhead

Each span has minimal overhead (~1-5 microseconds), but consider:

- Don't create spans for trivial operations (< 1ms)
- Batch process spans if processing thousands of items
- Use sampling in production for high-traffic endpoints

### Attribute Limits

- Keep attribute values reasonably sized (< 1KB)
- Don't add full response bodies as attributes
- Use events for milestone tracking, not all log statements

### When to Instrument

**DO instrument:**
- Database queries
- External HTTP calls
- AI/ML operations
- File I/O operations
- Cache operations
- Significant business logic

**DON'T instrument:**
- Simple variable assignments
- Trivial calculations
- Every function call
- Loop iterations (unless processing batches)

## Instrumenting Other Services

To add custom instrumentation to Controller, TextAnalyzer, or Scheduler:

1. **Import tracing package:**
   ```go
   import (
       "github.com/docutag/platform/pkg/tracing"
       "go.opentelemetry.io/otel/attribute"
   )
   ```

2. **Add to handler functions:**
   ```go
   func (h *Handler) HandleRequest(w http.ResponseWriter, r *http.Request) {
       // Add attributes to HTTP span
       tracing.SetSpanAttributes(r.Context(),
           attribute.String("request.id", requestID))

       // Create custom spans for operations
       ctx, span := tracing.StartSpan(r.Context(), "operation")
       defer span.End()

       // Your code here...
   }
   ```

3. **Rebuild and deploy:**
   ```bash
   docker-compose build <service>
   docker-compose up -d <service>
   ```

## Debugging with Traces

### Finding Slow Operations

1. Search Tempo for traces > 1 second
2. Examine span durations to find bottlenecks
3. Check attributes to understand context

### Diagnosing Errors

1. Filter by `status.code=ERROR`
2. Examine error attributes
3. Check sequence of operations before error
4. Review related logs via trace-to-log correlation

### Understanding Dependencies

1. View service map in Grafana
2. Trace requests across service boundaries
3. Identify which services are called
4. Measure cross-service latency

## Best Practices Summary

1. **Start broad, then refine**: Begin with coarse-grained spans, add detail where needed
2. **Use consistent naming**: Follow conventions for span names and attributes
3. **Add context**: Include relevant attributes (IDs, counts, URLs)
4. **Record errors**: Always use `RecordError` for failures
5. **Mark milestones**: Use events for important state changes
6. **Close spans**: Always call `span.End()`, prefer `defer`
7. **Propagate context**: Pass `ctx` through function calls
8. **Test locally**: Use Grafana Tempo to verify traces before deploying

## Examples from PurpleTab

Browse the source code for real-world examples:

- **Scraper**: `apps/scraper/api/server.go` - Database checks, scraping, saving
- **Controller**: (can be enhanced) - Request orchestration
- **TextAnalyzer**: (can be enhanced) - AI analysis operations
- **Scheduler**: (can be enhanced) - Task scheduling

## References

- [OpenTelemetry Tracing Specification](https://opentelemetry.io/docs/specs/otel/trace/)
- [Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [Grafana Tempo Query Language](https://grafana.com/docs/tempo/latest/traceql/)
- [PurpleTab Basic Tracing](./TRACING.md)
