# Frontend Monitoring Guide

This document outlines methods for collecting and displaying metrics for the PurpleTab React frontend.

## Overview

Frontend monitoring helps track user experience, performance, and application health. PurpleTab's web interface would benefit from metrics on:
- Page load times
- API call performance
- User interactions
- Error rates
- Real User Monitoring (RUM)

## Recommended Approaches

### 1. **OpenTelemetry Web SDK** (Recommended)

Integrate with the existing Tempo/Grafana stack for unified observability.

**Installation:**
```bash
cd apps/web
npm install @opentelemetry/api @opentelemetry/sdk-trace-web @opentelemetry/instrumentation-fetch @opentelemetry/instrumentation-xml-http-request @opentelemetry/context-zone @opentelemetry/exporter-trace-otlp-http
```

**Implementation:**
```typescript
// src/monitoring/telemetry.ts
import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { XMLHttpRequestInstrumentation } from '@opentelemetry/instrumentation-xml-http-request';
import { ZoneContextManager } from '@opentelemetry/context-zone';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';

const provider = new WebTracerProvider({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'docutag-web',
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
  }),
});

// Export to Tempo via OTLP
const exporter = new OTLPTraceExporter({
  url: 'http://localhost:4318/v1/traces',
});

provider.addSpanProcessor(new BatchSpanProcessor(exporter));

provider.register({
  contextManager: new ZoneContextManager(),
});

// Auto-instrument fetch and XHR requests
registerInstrumentations({
  instrumentations: [
    new FetchInstrumentation({
      propagateTraceHeaderCorsUrls: [/localhost:9080/],
      clearTimingResources: true,
    }),
    new XMLHttpRequestInstrumentation({
      propagateTraceHeaderCorsUrls: [/localhost:9080/],
    }),
  ],
});

export const tracer = provider.getTracer('docutag-web');
```

**Usage in Components:**
```typescript
import { tracer } from '@/monitoring/telemetry';

function ScrapeRequestForm() {
  const handleSubmit = async (data) => {
    const span = tracer.startSpan('scrape_request_submit');

    try {
      await api.createScrapeRequest(data);
      span.setStatus({ code: SpanStatusCode.OK });
    } catch (error) {
      span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
      span.recordException(error);
    } finally {
      span.end();
    }
  };
}
```

**Benefits:**
- Integrates with existing Tempo/Grafana infrastructure
- Distributed tracing across frontend and backend
- Standard OpenTelemetry format
- No additional services needed

---

### 2. **Web Vitals + Custom Metrics API**

Track Core Web Vitals and send to backend for Prometheus collection.

**Installation:**
```bash
npm install web-vitals
```

**Implementation:**
```typescript
// src/monitoring/webVitals.ts
import { getCLS, getFID, getFCP, getLCP, getTTFB, Metric } from 'web-vitals';

const sendToAnalytics = (metric: Metric) => {
  // Send to backend endpoint that exposes metrics to Prometheus
  fetch('/api/metrics', {
    method: 'POST',
    body: JSON.stringify({
      name: metric.name,
      value: metric.value,
      rating: metric.rating,
      delta: metric.delta,
      id: metric.id,
    }),
    headers: { 'Content-Type': 'application/json' },
  }).catch(console.error);
};

export function initWebVitals() {
  getCLS(sendToAnalytics);  // Cumulative Layout Shift
  getFID(sendToAnalytics);  // First Input Delay
  getFCP(sendToAnalytics);  // First Contentful Paint
  getLCP(sendToAnalytics);  // Largest Contentful Paint
  getTTFB(sendToAnalytics); // Time to First Byte
}
```

**Backend Endpoint (Controller Service):**
```go
// Create a new endpoint in Controller to collect web vitals
type WebVitalMetric struct {
    Name   string  `json:"name"`
    Value  float64 `json:"value"`
    Rating string  `json:"rating"`
}

var (
    webVitalsHistogram = promauto.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "web_vitals_seconds",
            Help:    "Core Web Vitals metrics",
            Buckets: []float64{0.1, 0.25, 0.5, 1, 2.5, 5, 10},
        },
        []string{"metric_name", "rating"},
    )
)

func handleWebVitals(w http.ResponseWriter, r *http.Request) {
    var metric WebVitalMetric
    json.NewDecoder(r.Body).Decode(&metric)

    webVitalsHistogram.WithLabelValues(metric.Name, metric.Rating).
        Observe(metric.Value / 1000) // Convert ms to seconds

    w.WriteHeader(http.StatusAccepted)
}
```

**Benefits:**
- Tracks actual user experience (RUM)
- Google's recommended metrics
- Direct Prometheus integration
- Lightweight implementation

---

### 3. **React Error Boundary + Error Tracking**

Monitor React errors and exceptions.

**Implementation:**
```typescript
// src/monitoring/ErrorBoundary.tsx
import { Component, ReactNode } from 'react';
import { tracer } from './telemetry';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error?: Error;
}

class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: any) {
    // Log to telemetry
    const span = tracer.startSpan('react_error');
    span.recordException(error);
    span.setAttribute('componentStack', errorInfo.componentStack);
    span.end();

    // Send to backend metrics
    fetch('/api/errors', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        error: error.message,
        stack: error.stack,
        componentStack: errorInfo.componentStack,
        timestamp: Date.now(),
      }),
    }).catch(console.error);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="error-fallback">
          <h2>Something went wrong</h2>
          <details>
            <summary>Error details</summary>
            <pre>{this.state.error?.message}</pre>
          </details>
        </div>
      );
    }

    return this.props.children;
  }
}

export default ErrorBoundary;
```

**Usage:**
```tsx
// src/main.tsx
import ErrorBoundary from './monitoring/ErrorBoundary';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <ErrorBoundary>
    <App />
  </ErrorBoundary>
);
```

---

### 4. **Custom Performance Monitoring Hook**

Track component render times and API call performance.

**Implementation:**
```typescript
// src/hooks/usePerformanceMonitor.ts
import { useEffect } from 'react';
import { tracer } from '@/monitoring/telemetry';

export function usePerformanceMonitor(componentName: string) {
  useEffect(() => {
    const span = tracer.startSpan(`render_${componentName}`);
    const startTime = performance.now();

    return () => {
      const duration = performance.now() - startTime;
      span.setAttribute('duration_ms', duration);
      span.end();

      // Also send to custom metrics
      if (duration > 100) { // Alert on slow renders
        console.warn(`${componentName} took ${duration}ms to render`);
      }
    };
  }, [componentName]);
}

// API call tracking
export function useApiCall<T>(
  apiFunc: () => Promise<T>,
  operationName: string
) {
  return async (...args: any[]) => {
    const span = tracer.startSpan(`api_${operationName}`);
    const startTime = performance.now();

    try {
      const result = await apiFunc(...args);
      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (error) {
      span.setStatus({ code: SpanStatusCode.ERROR });
      span.recordException(error as Error);
      throw error;
    } finally {
      const duration = performance.now() - startTime;
      span.setAttribute('duration_ms', duration);
      span.end();
    }
  };
}
```

**Usage:**
```typescript
function ScrapeRequestList() {
  usePerformanceMonitor('ScrapeRequestList');

  const fetchRequests = useApiCall(
    () => api.getScrapeRequests(),
    'fetch_scrape_requests'
  );

  // ... component logic
}
```

---

### 5. **User Session Analytics**

Track user behavior and session metrics.

**Implementation:**
```typescript
// src/monitoring/sessionAnalytics.ts
interface SessionMetrics {
  sessionId: string;
  pageViews: number;
  actions: string[];
  duration: number;
  scrapeRequestsCreated: number;
  searchesPerformed: number;
}

class SessionAnalytics {
  private sessionId: string;
  private metrics: SessionMetrics;
  private startTime: number;

  constructor() {
    this.sessionId = crypto.randomUUID();
    this.startTime = Date.now();
    this.metrics = {
      sessionId: this.sessionId,
      pageViews: 0,
      actions: [],
      duration: 0,
      scrapeRequestsCreated: 0,
      searchesPerformed: 0,
    };

    // Send metrics periodically
    setInterval(() => this.sendMetrics(), 30000);

    // Send on page unload
    window.addEventListener('beforeunload', () => this.sendMetrics());
  }

  trackPageView(page: string) {
    this.metrics.pageViews++;
    this.metrics.actions.push(`view:${page}`);
  }

  trackAction(action: string) {
    this.metrics.actions.push(action);

    if (action === 'scrape_request_created') {
      this.metrics.scrapeRequestsCreated++;
    } else if (action === 'search_performed') {
      this.metrics.searchesPerformed++;
    }
  }

  private sendMetrics() {
    this.metrics.duration = Date.now() - this.startTime;

    fetch('/api/analytics', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(this.metrics),
    }).catch(console.error);
  }
}

export const sessionAnalytics = new SessionAnalytics();
```

---

## Grafana Dashboard for Frontend Metrics

Once metrics are collected, create a Grafana dashboard to visualize:

### Panels to Include:
1. **Core Web Vitals**
   - LCP, FID, CLS histograms
   - Performance score over time

2. **API Call Performance**
   - Request duration by endpoint
   - Success/error rates
   - Request volume

3. **Error Tracking**
   - Error rate over time
   - Error types distribution
   - Component error breakdown

4. **User Engagement**
   - Active sessions
   - Page views
   - Feature usage (scrapes created, searches)

5. **Performance Metrics**
   - Component render times
   - Bundle size impact
   - Memory usage

---

## Implementation Recommendation

**Phase 1: Essential Monitoring** (Implement First)
1. OpenTelemetry Web SDK for distributed tracing
2. Error Boundary for error tracking
3. Web Vitals for performance monitoring

**Phase 2: Enhanced Analytics** (Add Later)
1. Custom performance hooks
2. Session analytics
3. User behavior tracking

**Phase 3: Advanced Features**
1. A/B test tracking
2. Feature flag analytics
3. Custom business metrics

---

## Alternative: Managed Solutions

If you prefer turnkey solutions:

- **Sentry** - Error tracking + performance monitoring
- **DataDog RUM** - Full real user monitoring
- **New Relic Browser** - Complete frontend observability
- **LogRocket** - Session replay + monitoring
- **PostHog** - Product analytics + feature flags

These integrate easily but add external dependencies and costs.

---

## Next Steps

1. Choose approach based on requirements
2. Implement Phase 1 monitoring
3. Create Grafana dashboard for frontend metrics
4. Set up alerts for critical metrics (error rates, performance degradation)
5. Iterate based on insights

For questions or implementation help, see the main [Observability section in README.md](../README.md#observability).
