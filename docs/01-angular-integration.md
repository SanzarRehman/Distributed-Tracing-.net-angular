# Angular + OpenTelemetry Integration Guide

Complete guide for adding distributed tracing to any Angular application.

---

## Prerequisites

- Angular 16+ (works with Angular 19)
- Node.js 18+
- OpenTelemetry collector or Jaeger with OTLP endpoint

---

## 1. Install Dependencies

```bash
npm install @opentelemetry/api \
  @opentelemetry/sdk-trace-web \
  @opentelemetry/sdk-trace-base \
  @opentelemetry/instrumentation-fetch \
  @opentelemetry/instrumentation-xml-http-request \
  @opentelemetry/exporter-trace-otlp-http \
  @opentelemetry/resources \
  @opentelemetry/semantic-conventions \
  @opentelemetry/context-zone \
  @opentelemetry/instrumentation
```

---

## 2. Create Tracing Initialization File

**`src/tracing.ts`**

```typescript
import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { XMLHttpRequestInstrumentation } from '@opentelemetry/instrumentation-xml-http-request';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';
import { ZoneContextManager } from '@opentelemetry/context-zone';

// 1. Define your service resource
const resource = resourceFromAttributes({
  [ATTR_SERVICE_NAME]: 'my-angular-app',  // ⬅️ Change this to your app name
});

// 2. Configure OTLP exporter (points to Jaeger/collector)
const exporter = new OTLPTraceExporter({
  url: 'http://localhost:4318/v1/traces',  // ⬅️ Update if using different endpoint
});

// 3. Create tracer provider with batch processor
const provider = new WebTracerProvider({
  resource,
  spanProcessors: [new BatchSpanProcessor(exporter)],
});

// 4. Register with Zone.js for Angular change detection compatibility
provider.register({
  contextManager: new ZoneContextManager(),
});

// 5. Auto-instrument HTTP calls
registerInstrumentations({
  instrumentations: [
    new FetchInstrumentation({
      propagateTraceHeaderCorsUrls: [
        new RegExp('http://localhost:5215.*') // ⬅️ Explicitly allow API origin
      ],
      clearTimingResources: true,
    }),
    new XMLHttpRequestInstrumentation({
      propagateTraceHeaderCorsUrls: [
        new RegExp('http://localhost:5215.*')
      ],
    }),
  ],
});

console.log('[Tracing] OpenTelemetry initialized');
```

---

## 3. Import Tracing Before Angular Bootstrap

**`src/main.ts`**

```typescript
import './tracing';  // ⬅️ Import FIRST, before Angular

import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { AppComponent } from './app/app.component';

bootstrapApplication(AppComponent, appConfig)
  .catch((err) => console.error(err));
```

> **Why first?** Tracing must initialize before Angular's HTTP module to intercept all requests.

---

## 4. Configure CORS (Jaeger/Collector)

If using **Jaeger all-in-one** with OTLP HTTP, add CORS environment variables:

**`docker-compose.yml`**

```yaml
services:
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"   # UI
      - "4318:4318"     # OTLP HTTP
    environment:
      - COLLECTOR_OTLP_ENABLED=true
      - COLLECTOR_OTLP_HTTP_CORS_ALLOWED_ORIGINS=http://localhost:4200
      - COLLECTOR_OTLP_HTTP_CORS_ALLOWED_HEADERS=content-type
```

> **Important:** Use **exact origin** (`http://localhost:4200`), not `*`, when Jaeger sends `Access-Control-Allow-Credentials: true`.

---

## 5. Add Global Error Handler (Recommended)

Automatically trace **all errors** to Jaeger with **zero per-component code**. This single handler captures:
- ✅ Uncaught exceptions (TypeError, ReferenceError, etc.)
- ✅ Unhandled promise rejections
- ✅ Resource load failures (images, scripts, stylesheets)

**`src/app/global-error-handler.ts`**

```typescript
import { ErrorHandler, Injectable } from '@angular/core';
import { trace, SpanStatusCode } from '@opentelemetry/api';

@Injectable()
export class GlobalErrorHandler implements ErrorHandler {
  private tracer = trace.getTracer('my-angular-app');

  constructor() {
    // Catch unhandled promise rejections globally
    window.addEventListener('unhandledrejection', (event: PromiseRejectionEvent) => {
      const error = event.reason;
      const span = this.tracer.startSpan('unhandled-promise-rejection');
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error?.message || String(error),
      });
      if (error instanceof Error) {
        span.recordException(error);
      }
      span.end();
    });

    // Catch resource load failures (images, scripts, etc.)
    window.addEventListener('error', (event: ErrorEvent) => {
      const target = event.target as HTMLElement;
      if (target && target !== window as any
          && (target.tagName === 'IMG' || target.tagName === 'SCRIPT' || target.tagName === 'LINK')) {
        const span = this.tracer.startSpan('resource-load-failure');
        span.setAttribute('resource.type', target.tagName.toLowerCase());
        span.setAttribute('resource.src', (target as any).src || (target as any).href || 'unknown');
        span.setStatus({
          code: SpanStatusCode.ERROR,
          message: `Failed to load ${target.tagName.toLowerCase()}`,
        });
        span.end();
      }
    }, true);  // capture phase to catch resource errors
  }

  // Catches all uncaught exceptions from Angular zone
  handleError(error: any): void {
    const span = this.tracer.startSpan('uncaught-error');
    span.setStatus({
      code: SpanStatusCode.ERROR,
      message: error.message || 'Unknown error',
    });
    span.recordException(error);
    span.end();

    // Show error in browser console naturally
    setTimeout(() => { throw error; });
  }
}
```

**`src/app/app.config.ts`**

```typescript
import { ApplicationConfig, ErrorHandler } from '@angular/core';
import { provideHttpClient } from '@angular/common/http';
import { GlobalErrorHandler } from './global-error-handler';

export const appConfig: ApplicationConfig = {
  providers: [
    provideHttpClient(withFetch()), // ⬅️ Enable Fetch API for better tracing
    { provide: ErrorHandler, useClass: GlobalErrorHandler },
  ],
};
```

> **No extra code needed!** Any error in your app automatically creates a span in Jaeger and appears in the browser console. No try-catch, no manual spans for errors.

---

## 6. Create Manual Spans (Optional)

For **non-error** operations you want to trace (e.g., business logic, performance tracking):

**`src/app/my.service.ts`**

```typescript
import { Injectable } from '@angular/core';
import { trace, SpanStatusCode } from '@opentelemetry/api';

@Injectable({ providedIn: 'root' })
export class MyService {
  private tracer = trace.getTracer('my-angular-app');

  performComplexOperation() {
    const span = this.tracer.startSpan('complex-operation');
    span.setAttribute('user.id', '12345');

    // Your logic here — errors will be caught by GlobalErrorHandler automatically
    const result = this.doWork();

    span.setStatus({ code: SpanStatusCode.OK });
    span.end();
    return result;
  }

  private doWork() {
    return Math.random();
  }
}
```

---

## 7. Verify Traces

1. **Start Jaeger:** `docker compose up -d`
2. **Start Angular:** `ng serve`
3. **Trigger HTTP requests** from your app
4. **Open Jaeger UI:** http://localhost:16686
5. **Select service:** `my-angular-app`
6. **View traces** with spans for all HTTP calls

---

---

## 8. Runtime Configuration (Docker/K8s)

To allow changing API and OTel URLs without rebuilding the app, we use a **Runtime Configuration** pattern:

1.  **`src/assets/env.js`**: Contains default local values. Loaded in `index.html`.
2.  **`src/assets/env.template.js`**: Contains placeholders (`${API_URL}`) for `envsubst`.
3.  **`Dockerfile`**: Replaces placeholders at startup using environment variables.

**Usage:**

```typescript
// In your code (e.g. tracing.ts)
const env = (window as any).env || {
  API_URL: 'http://localhost:5215',
  OTEL_URL: 'http://localhost:4318/v1/traces'
};
```

**Deployment:**
Simply set `API_URL` and `OTEL_URL` environment variables in your `docker-compose.yml` or K8s manifest.

---

## Configuration Reference

| Option | Description | Default |
|--------|-------------|---------|
| `ATTR_SERVICE_NAME` | Service name in Jaeger | `unknown_service` |
| `exporter.url` | OTLP endpoint | `http://localhost:4318/v1/traces` |
| `propagateTraceHeaderCorsUrls` | Origins to send trace headers | `[]` |
| `BatchSpanProcessor` | Batches spans before export | Enabled |
| `ZoneContextManager` | Angular Zone.js compatibility | Required |

---

## Troubleshooting

### CORS Errors

**Error:** `Access to resource at 'http://localhost:4318/v1/traces' blocked by CORS`

**Solution:** Configure Jaeger with exact origin:
```yaml
- COLLECTOR_OTLP_HTTP_CORS_ALLOWED_ORIGINS=http://localhost:4200
- COLLECTOR_OTLP_HTTP_CORS_ALLOWED_HEADERS=content-type
```

### No Traces Appearing

1. **Check console** for export errors
2. **Verify Jaeger is running:** `docker ps`
3. **Test OTLP endpoint:** `curl http://localhost:4318/v1/traces`
4. **Hard refresh browser** (Cmd+Shift+R / Ctrl+Shift+R)

### Wildcard Origin Error

**Error:** `The value of the 'Access-Control-Allow-Origin' header must not be '*' when credentials mode is 'include'`

**Solution:** Use explicit origin instead of `*`

---

### UI Stuck on Loading / Not Updating

**Issue:** UI state (e.g., loading spinners) doesn't update after an error or async operation, especially when using `Status` variables modified inside callbacks.

**Cause:**
- **Zoneless:** Async callbacks do NOT trigger change detection.
- **Zoned:** Some third-party libraries (like OTel) might sometimes break Zone context.

**Solution:** Inject `ChangeDetectorRef` and force an update.

```typescript
import { ChangeDetectorRef } from '@angular/core';

export class AppComponent {
  constructor(private cdr: ChangeDetectorRef) {}

  doOperation() {
    this.status = 'loading';
    this.apiCall().subscribe({
      next: () => {
        this.status = 'success';
        this.cdr.detectChanges(); // ⬅️ Force update
      },
      error: () => {
        this.status = 'error';
        this.cdr.detectChanges(); // ⬅️ Force update
      }
    });
  }
}

---

## Next Steps
- **Advanced:** [Sampling, filtering, custom processors](./03-advanced-configuration.md)
- **.NET Integration:** [Add backend tracing](./02-dotnet-integration.md)
- **Protocol Details:** [OpenTelemetry fundamentals](./04-opentelemetry-fundamentals.md)
