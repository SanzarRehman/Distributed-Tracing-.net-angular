# Angular (Zoneless) + OpenTelemetry Integration

Complete guide for adding distributed tracing to an **Angular 18+ Zoneless** application.

---

## 1. Prerequisites

- Angular 18+ (Zoneless enabled)
- Node.js 18+
- OpenTelemetry collector or Jaeger

---

## 2. Dependencies

Same as standard Angular, but **omit** `@opentelemetry/context-zone`.

```bash
npm install @opentelemetry/api \
  @opentelemetry/sdk-trace-web \
  @opentelemetry/sdk-trace-base \
  @opentelemetry/instrumentation-fetch \
  @opentelemetry/instrumentation-xml-http-request \
  @opentelemetry/exporter-trace-otlp-http \
  @opentelemetry/resources \
  @opentelemetry/semantic-conventions \
  @opentelemetry/instrumentation
```

---

## 3. Tracing Setup (`tracing.ts`)

**Key Difference:** Do NOT import `ZoneContextManager`. Use the default `StackContextManager` (by calling `provider.register()` without arguments).

```typescript
import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { XMLHttpRequestInstrumentation } from '@opentelemetry/instrumentation-xml-http-request';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

const resource = resourceFromAttributes({
  [ATTR_SERVICE_NAME]: 'pathfinder-ui-zoneless',
});

const exporter = new OTLPTraceExporter({
  url: 'http://localhost:4318/v1/traces',
});

const provider = new WebTracerProvider({
  resource,
  spanProcessors: [new BatchSpanProcessor(exporter)],
});

// ✅ REGISTER WITHOUT CONTEXT MANAGER (Uses StackContextManager)
provider.register();

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
```

---

## 4. Bootstrap (`main.ts`)

Import tracing **before** bootstrapping the application.

```typescript
import './tracing'; // ⬅️ Must be first

import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { AppComponent } from './app/app.component';

bootstrapApplication(AppComponent, appConfig)
  .catch((err) => console.error(err));
```

---

## 5. Zoneless Configuration (`app.config.ts`)

Ensure `provideExperimentalZonelessChangeDetection()` is used.

```typescript
import { ApplicationConfig, provideExperimentalZonelessChangeDetection, ErrorHandler } from '@angular/core';
import { provideHttpClient, withFetch } from '@angular/common/http';
import { GlobalErrorHandler } from './global-error-handler';

export const appConfig: ApplicationConfig = {
  providers: [
    provideExperimentalZonelessChangeDetection(), // ⬅️ Enables Zoneless
    provideHttpClient(withFetch()), // ⬅️ Enable Fetch API for better tracing
    { provide: ErrorHandler, useClass: GlobalErrorHandler },
  ]
};
```

---

## 6. Global Error Handler

The **exact same** `GlobalErrorHandler` works for Zoneless because it uses native window listeners (`unhandledrejection`, `error`) instead of relying on Zone.js.

See the [Standard Angular Guide](./01-angular-integration.md#5-add-global-error-handler-recommended) for implementation details.

---

## 7. Important! UI Updates

In Zoneless mode, async callbacks (like HTTP subscriptions) **do not** automatically trigger change detection. If you update UI state in a callback, you **MUST** trigger it manually or use Signals.

**Using ChangeDetectorRef (Recommended for callbacks):**

```typescript
import { ChangeDetectorRef } from '@angular/core';

export class AppComponent {
  constructor(private cdr: ChangeDetectorRef) {}

  doSomething() {
    this.status = 'loading';
    this.api.call().subscribe({
      next: () => {
        this.status = 'success';
        this.cdr.detectChanges(); // ⬅️ Required in Zoneless!
      },
      error: () => {
        this.status = 'error';
        this.cdr.detectChanges(); // ⬅️ Required in Zoneless!
      }
    });
  }
}
```

**Using Signals (Alternative):**
Updating a Signal automatically schedules a UI update in Zoneless mode.

---

## 8. Verification

1. Run app: `ng serve`
2. Check console: `[Tracing] OpenTelemetry initialized` (if you added log)
3. Check **no zone.js** loaded in network tab
---

## 9. Runtime Configuration (Docker/K8s)

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
