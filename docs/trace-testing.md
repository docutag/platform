# Trace Testing Documentation

## Overview

Comprehensive end-to-end trace tests have been implemented to verify OpenTelemetry distributed tracing across the entire DocuTab system.

## Test Coverage

### Backend Services

#### Controller (`apps/controller/internal/queue/trace_e2e_test.go`)
- **TestTraceContextPropagation_Enqueue** - Verifies trace context is captured when enqueuing scrape and extract link tasks
- **TestTraceContextPropagation_Extract** - Verifies workers can extract trace context from task payloads
- **TestQueueWaitTimeCalculation** - Verifies queue wait time calculation accuracy
- **TestE2ETraceFlow_ScrapeRequest** - Complete trace flow from HTTP request → queue → worker
- **TestE2ETraceFlow_ExtractLinks** - Complete trace flow for link extraction tasks
- **TestE2ETraceFlowWithRealAsynq** - Integration test with real Redis/Asynq (requires Redis)

#### TextAnalyzer (`apps/textanalyzer/internal/queue/trace_e2e_test.go`)
- **TestTraceContextPropagation_Enqueue** - Verifies trace context capture for all 3 task types
- **TestTraceContextPropagation_Extract** - Verifies trace context extraction for all 3 task types
- **TestQueueWaitTimeCalculation** - Verifies wait time calculation
- **TestE2ETraceFlow_ProcessDocument** - Complete trace flow for document processing
- **TestE2ETraceFlow_EnrichText** - Complete trace flow for text enrichment
- **TestE2ETraceFlow_EnrichImage** - Complete trace flow for image enrichment
- **TestE2EMultiTaskTrace** - Verifies trace propagation across multiple related tasks
- **TestE2EQueueWaitTimeAccuracy** - Tests wait time measurement with various durations
- **TestE2ETraceFlowWithRealAsynq** - Integration test with real Asynq

### Web Frontend (`apps/web/src/utils/tracing.test.js`)

#### Tracing Utilities
- **initTracing** - Verifies OpenTelemetry initialization
- **getTracer** - Verifies tracer instance retrieval
- **withSpan** - Verifies span creation and context management
- **getTraceContext** - Verifies trace context extraction
- **shutdownTracing** - Verifies graceful shutdown

#### End-to-End Trace Flow
- **Nested span propagation** - Verifies TraceID propagation through nested operations
- **Sequential operations** - Verifies multiple sequential traced operations
- **Async boundaries** - Verifies trace context preservation across async/await

#### Error Handling & Performance
- **Missing environment variables** - Graceful degradation
- **Span creation errors** - Error handling
- **Performance impact** - Overhead measurement
- **High volume** - Scalability testing

## Running Tests

### Individual Service Tests

```bash
# Controller trace tests
cd apps/controller
make test-trace              # Run trace propagation tests
make test-trace-e2e          # Run E2E trace flow tests

# TextAnalyzer trace tests
cd apps/textanalyzer
make test-trace
make test-trace-e2e

# Web frontend trace tests
cd apps/web
npm test -- tracing.test.js --run
```

### All Services

```bash
# From root directory
make test-trace              # Run trace tests across all services
make test-trace-e2e          # Run E2E trace tests for Go services
```

### Composite Stages

Trace tests are automatically run as part of these composite stages:

```bash
make check                   # Run all quality checks (fmt, lint, test, trace)
make docker-build            # Run tests + trace tests before Docker build
make docker-rebuild          # Run tests + trace tests before rebuild
make docker-staging-build    # Run tests + trace tests before staging build
make docker-staging-push     # Run tests + trace tests before push
make docker-staging-deploy   # Run tests + trace tests before deployment
```

## CI/CD Integration

Trace tests are integrated into GitHub Actions workflows:

- **`.github/workflows/test-controller.yml`** - Runs trace tests for Controller
- **`.github/workflows/test-textanalyzer.yml`** - Runs trace tests for TextAnalyzer
- **`.github/workflows/test-web.yml`** - Runs tracing tests for Web frontend

Tests run automatically on:
- Push to main/master/develop branches
- Pull requests
- Manual workflow dispatch

## What Tests Verify

### 1. Trace Context Capture
- TraceID and SpanID are extracted from active span context
- Trace context is serialized into task payload JSON
- EnqueuedAt timestamp is recorded for queue wait time metrics

### 2. Trace Context Propagation
- Task payloads contain valid trace IDs
- TraceIDs match the parent span
- SpanIDs match the enqueue span

### 3. Trace Context Extraction
- Workers can deserialize trace context from payloads
- Remote span contexts can be reconstructed from hex strings
- Trace flags (sampling) are preserved

### 4. Queue Wait Time Calculation
- EnqueuedAt timestamp enables wait time measurement
- Wait times are calculated correctly for various durations
- Wait times are logged and recorded in trace spans

### 5. End-to-End Trace Chains
- All spans in a trace share the same TraceID
- Parent-child relationships are maintained
- Traces link across service boundaries (HTTP → Queue → Worker)
- Browser → Backend → Queue spans form complete trace tree

## Test Results Summary

### Controller
✅ **All tests passing**
- ✅ TestTraceContextPropagation_Enqueue (2 subtests)
- ✅ TestTraceContextPropagation_Extract (2 subtests)
- ✅ TestE2ETraceFlow_ScrapeRequest
- ✅ TestE2ETraceFlow_ExtractLinks
- ✅ TestE2ETraceFlowWithRealAsynq (skips if Redis unavailable)

### TextAnalyzer
✅ **All tests passing**, covering all 3 task types:
- ✅ TestTraceContextPropagation_Enqueue (3 subtests: ProcessDocument, EnrichText, EnrichImage)
- ✅ TestTraceContextPropagation_Extract (3 subtests: ProcessDocument, EnrichText, EnrichImage)
- ✅ TestE2ETraceFlow_ProcessDocument
- ✅ TestE2ETraceFlow_EnrichText
- ✅ TestE2ETraceFlow_EnrichImage
- ✅ TestE2EMultiTaskTrace (tests propagation across multiple related tasks)
- ✅ TestE2EQueueWaitTimeAccuracy
- ✅ TestE2ETraceFlowWithRealAsynq (skips if Redis unavailable)

### Web Frontend
Tests implemented for:
- OpenTelemetry initialization
- Span creation and management
- Trace context propagation
- Error handling
- Performance and scalability

## Implementation Details

### Trace Context Fields

All task payloads include these tracing fields:

```go
type TaskPayload struct {
    // ... task-specific fields ...

    // Tracing and timing fields
    TraceID    string `json:"trace_id,omitempty"`
    SpanID     string `json:"span_id,omitempty"`
    EnqueuedAt int64  `json:"enqueued_at"` // Unix timestamp in nanoseconds
}
```

### Trace Context Capture (Enqueue)

```go
// Add tracing context if available
if span := trace.SpanFromContext(ctx); span.SpanContext().IsValid() {
    spanCtx := span.SpanContext()
    payload.TraceID = spanCtx.TraceID().String()
    payload.SpanID = spanCtx.SpanID().String()

    // Record enqueue event
    span.AddEvent("task_enqueued", trace.WithAttributes(
        attribute.String("task.type", TypeProcessDocument),
        attribute.String("task.id", analysisID),
        attribute.Int64("enqueued_at", payload.EnqueuedAt),
    ))
}
```

### Trace Context Extraction (Worker)

```go
// Extract trace context from payload
var remoteSpanCtx trace.SpanContext
if payload.TraceID != "" && payload.SpanID != "" {
    traceID, _ := trace.TraceIDFromHex(payload.TraceID)
    spanID, _ := trace.SpanIDFromHex(payload.SpanID)

    remoteSpanCtx = trace.NewSpanContext(trace.SpanContextConfig{
        TraceID:    traceID,
        SpanID:     spanID,
        TraceFlags: trace.FlagsSampled,
        Remote:     true,
    })

    ctx = trace.ContextWithRemoteSpanContext(ctx, remoteSpanCtx)
}

// Calculate queue wait time
var queueWaitTime time.Duration
if payload.EnqueuedAt > 0 {
    enqueuedTime := time.Unix(0, payload.EnqueuedAt)
    queueWaitTime = time.Since(enqueuedTime)
}

// Create worker span with link to enqueue span
ctx, span := otel.Tracer("service").Start(ctx, "asynq.task.process",
    trace.WithSpanKind(trace.SpanKindConsumer),
    trace.WithAttributes(
        attribute.Float64("queue.wait_time_seconds", queueWaitTime.Seconds()),
    ),
)
defer span.End()
```

## Future Enhancements

Optional improvements for the future:

1. **Performance benchmarks** - Measure tracing overhead under load
2. **Trace sampling tests** - Verify sampling decisions propagate correctly
3. **Error trace tests** - Verify failed operations are properly traced
4. **Multi-hop trace tests** - Verify traces across 3+ service hops
5. **Trace export tests** - Verify traces reach Tempo/OTLP endpoint

## Related Documentation

- [Asynq OpenTelemetry Integration](./asynq-otel-integration.md) - Full integration documentation
- [OpenTelemetry Web SDK Documentation](https://opentelemetry.io/docs/instrumentation/js/)
- [Asynq Documentation](https://github.com/hibiken/asynq)
