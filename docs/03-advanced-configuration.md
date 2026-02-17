# Advanced OpenTelemetry Configuration

Sampling strategies, filtering, customization, and performance tuning for production deployments.

---

## 1. Sampling Strategies

Control **which traces** are exported to reduce cost and noise.

### Always-On Sampler (Default)

Exports **every trace** (100% sampling).

```typescript
// Angular
import { AlwaysOnSampler } from '@opentelemetry/sdk-trace-base';

const provider = new WebTracerProvider({
  resource,
  sampler: new AlwaysOnSampler(),
});
```

```csharp
// .NET - default behavior, no extra config needed
```

---

### Probabilistic Sampler

Exports a **percentage** of traces (e.g., 10%).

```typescript
// Angular
import { TraceIdRatioBasedSampler } from '@opentelemetry/sdk-trace-base';

const provider = new WebTracerProvider({
  resource,
  sampler: new TraceIdRatioBasedSampler(0.1),  // 10% sampling
});
```

```csharp
// .NET
using OpenTelemetry.Trace;

.WithTracing(tracing => tracing
    .SetSampler(new TraceIdRatioBasedSampler(0.1))  // 10% sampling
    .AddOtlpExporter(...));
```

---

### Parent-Based Sampler

Respects **incoming trace decisions** from upstream services.

```typescript
// Angular
import { ParentBasedSampler, TraceIdRatioBasedSampler } from '@opentelemetry/sdk-trace-base';

const provider = new WebTracerProvider({
  sampler: new ParentBasedSampler({
    root: new TraceIdRatioBasedSampler(0.1),  // New traces: 10%
    // If parent sampled, child is sampled
  }),
});
```

```csharp
// .NET - ParentBasedSampler is the default
```

---

### Custom Sampler (Filter by Attribute)

Sample based on **span attributes** (e.g., only errors).

```typescript
// Angular
import { Sampler, SamplingDecision, SamplingResult } from '@opentelemetry/sdk-trace-base';

class ErrorOnlySampler implements Sampler {
  shouldSample(context: any, traceId: any, spanName: string, spanKind: any, attributes: any): SamplingResult {
    const isError = attributes['http.status_code'] >= 400;
    return {
      decision: isError ? SamplingDecision.RECORD_AND_SAMPLED : SamplingDecision.NOT_RECORD,
    };
  }

  toString(): string {
    return 'ErrorOnlySampler';
  }
}

const provider = new WebTracerProvider({
  sampler: new ErrorOnlySampler(),
});
```

```csharp
// .NET
using OpenTelemetry.Trace;

public class ErrorOnlySampler : Sampler
{
    public override SamplingResult ShouldSample(in SamplingParameters samplingParameters)
    {
        var isError = samplingParameters.Tags?.Any(t => 
            t.Key == "http.status_code" && int.Parse(t.Value?.ToString() ?? "0") >= 400) ?? false;

        return new SamplingResult(isError ? SamplingDecision.RecordAndSample : SamplingDecision.Drop);
    }
}

// In Program.cs
.WithTracing(tracing => tracing
    .SetSampler(new ErrorOnlySampler())
    .AddOtlpExporter(...));
```

---

## 2. Filtering Traces

### Filter by HTTP Status (Angular)

Exclude successful requests from auto-instrumentation.

```typescript
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';

registerInstrumentations({
  instrumentations: [
    new FetchInstrumentation({
      ignoreUrls: [/localhost:4200\/assets/],  // Ignore static assets
      applyCustomAttributesOnSpan: (span, request, response) => {
        if (response.status < 400) {
          span.setAttribute('filter.ignore', true);  // Mark for filtering
        }
      },
    }),
  ],
});
```

### Filter by HTTP Status (.NET)

Exclude health checks and successful requests.

```csharp
.WithTracing(tracing => tracing
    .AddAspNetCoreInstrumentation(options =>
    {
        options.Filter = (httpContext) =>
        {
            // Exclude health check endpoint
            if (httpContext.Request.Path.Value?.Contains("/health") == true)
                return false;

            // Exclude successful requests
            return httpContext.Response.StatusCode >= 400;
        };
    })
    .AddOtlpExporter(...));
```

---

## 3. Custom Span Processors

Modify or enrich spans **before export**.

### Add Custom Attributes (Angular)

```typescript
import { SpanProcessor, ReadableSpan } from '@opentelemetry/sdk-trace-base';

class CustomAttributeProcessor implements SpanProcessor {
  onStart(span: any): void {
    span.setAttribute('environment', 'production');
    span.setAttribute('app.version', '1.0.0');
  }

  onEnd(span: ReadableSpan): void {}
  forceFlush(): Promise<void> { return Promise.resolve(); }
  shutdown(): Promise<void> { return Promise.resolve(); }
}

const provider = new WebTracerProvider({
  spanProcessors: [
    new CustomAttributeProcessor(),
    new BatchSpanProcessor(exporter),
  ],
});
```

### Add Custom Attributes (.NET)

```csharp
using OpenTelemetry;
using System.Diagnostics;

public class CustomAttributeProcessor : BaseProcessor<Activity>
{
    public override void OnStart(Activity activity)
    {
        activity.SetTag("environment", "production");
        activity.SetTag("app.version", "1.0.0");
    }
}

// In Program.cs
.WithTracing(tracing => tracing
    .AddProcessor(new CustomAttributeProcessor())
    .AddOtlpExporter(...));
```

---

## 4. Resource Attributes

Identify your **service** in Jaeger with metadata.

### Angular

```typescript
import { resourceFromAttributes } from '@opentelemetry/resources';
import { 
  ATTR_SERVICE_NAME, 
  ATTR_SERVICE_VERSION,
  ATTR_DEPLOYMENT_ENVIRONMENT,
} from '@opentelemetry/semantic-conventions';

const resource = resourceFromAttributes({
  [ATTR_SERVICE_NAME]: 'pathfinder-ui',
  [ATTR_SERVICE_VERSION]: '1.2.3',
  [ATTR_DEPLOYMENT_ENVIRONMENT]: 'production',
  'service.namespace': 'frontend',
});
```

### .NET

```csharp
.ConfigureResource(resource => resource
    .AddService(
        serviceName: "pathfinder-api",
        serviceVersion: "1.2.3",
        serviceNamespace: "backend")
    .AddAttributes(new Dictionary<string, object>
    {
        ["deployment.environment"] = "production",
        ["host.name"] = Environment.MachineName,
    }))
```

---

## 5. Propagation Formats

Control **how trace context** is passed between services.

### W3C Trace Context (Default)

Standard format: `traceparent: 00-<trace-id>-<span-id>-01`

```typescript
// Angular - default, no config needed
```

```csharp
// .NET - default, no config needed
```

### B3 Format (Zipkin)

```typescript
// Angular
import { B3Propagator } from '@opentelemetry/propagator-b3';
import { propagation } from '@opentelemetry/api';

propagation.setGlobalPropagator(new B3Propagator());
```

```csharp
// .NET
dotnet add package OpenTelemetry.Extensions.Propagators

using OpenTelemetry.Extensions.Propagators;

builder.Services.AddOpenTelemetry()
    .ConfigureResource(...)
    .WithTracing(tracing => tracing
        .AddB3Propagator()  // Enable B3
        .AddOtlpExporter(...));
```

---

## 6. Performance Tuning

### Batch Span Processor (Recommended)

**Batches spans** before export to reduce network overhead.

```typescript
// Angular
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';

const provider = new WebTracerProvider({
  spanProcessors: [
    new BatchSpanProcessor(exporter, {
      maxQueueSize: 2048,           // Max spans in queue
      maxExportBatchSize: 512,      // Spans per batch
      scheduledDelayMillis: 5000,   // Export every 5 seconds
      exportTimeoutMillis: 30000,   // 30s timeout
    }),
  ],
});
```

```csharp
// .NET - BatchExportProcessor is the default
// Customize in appsettings.json:
{
  "OpenTelemetry": {
    "BatchExportProcessor": {
      "MaxQueueSize": 2048,
      "ScheduledDelayMillis": 5000,
      "ExporterTimeoutMillis": 30000,
      "MaxExportBatchSize": 512
    }
  }
}
```

### Simple Span Processor (Dev Only)

**Exports immediately** (useful for debugging).

```typescript
// Angular
import { SimpleSpanProcessor } from '@opentelemetry/sdk-trace-base';

const provider = new WebTracerProvider({
  spanProcessors: [new SimpleSpanProcessor(exporter)],  // No batching
});
```

```csharp
// .NET - not recommended, BatchProcessor is more efficient
```

---

## 7. Multiple Exporters

Send traces to **multiple backends** simultaneously.

```typescript
// Angular
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { ConsoleSpanExporter } from '@opentelemetry/sdk-trace-base';

const jaegerExporter = new OTLPTraceExporter({ url: 'http://localhost:4318/v1/traces' });
const consoleExporter = new ConsoleSpanExporter();

const provider = new WebTracerProvider({
  spanProcessors: [
    new BatchSpanProcessor(jaegerExporter),
    new BatchSpanProcessor(consoleExporter),  // Debug in console
  ],
});
```

```csharp
// .NET
.WithTracing(tracing => tracing
    .AddOtlpExporter(options => options.Endpoint = new Uri("http://localhost:4317"))
    .AddConsoleExporter());  // Debug in console
```

---

## 8. Environment-Based Configuration

### Angular

```typescript
// src/environments/environment.prod.ts
export const environment = {
  production: true,
  otlpEndpoint: 'https://my-collector.example.com/v1/traces',
  samplingRate: 0.1,  // 10% in prod
};

// src/tracing.ts
import { environment } from './environments/environment';

const exporter = new OTLPTraceExporter({
  url: environment.otlpEndpoint,
});

const provider = new WebTracerProvider({
  sampler: new TraceIdRatioBasedSampler(environment.samplingRate),
});
```

### .NET

```json
// appsettings.Production.json
{
  "OpenTelemetry": {
    "ServiceName": "pathfinder-api",
    "OtlpEndpoint": "https://my-collector.example.com:4317",
    "SamplingRate": 0.1
  }
}
```

```csharp
// Program.cs
var otlpEndpoint = builder.Configuration["OpenTelemetry:OtlpEndpoint"]!;
var samplingRate = double.Parse(builder.Configuration["OpenTelemetry:SamplingRate"]!);

.WithTracing(tracing => tracing
    .SetSampler(new TraceIdRatioBasedSampler(samplingRate))
    .AddOtlpExporter(options => options.Endpoint = new Uri(otlpEndpoint)));
```

---

## Summary Table

| Feature | Angular | .NET |
|---------|---------|------|
| **Sampling: Always-On** | `new AlwaysOnSampler()` | Default |
| **Sampling: Probabilistic** | `new TraceIdRatioBasedSampler(0.1)` | `.SetSampler(new TraceIdRatioBasedSampler(0.1))` |
| **Filtering by Status** | `FetchInstrumentation.applyCustomAttributesOnSpan` | `AddAspNetCoreInstrumentation(options => options.Filter)` |
| **Custom Processor** | `implements SpanProcessor` | `extends BaseProcessor<Activity>` |
| **Resource Attributes** | `resourceFromAttributes({ ... })` | `.AddService(...).AddAttributes(...)` |
| **Batch Processor** | `new BatchSpanProcessor(exporter, { ... })` | Default (configure in `appsettings.json`) |
| **Multiple Exporters** | Multiple `BatchSpanProcessor` | Chain `.AddOtlpExporter().AddConsoleExporter()` |

---

## Next Steps

- **Angular Basics:** [Angular integration guide](./01-angular-integration.md)
- **.NET Basics:** [.NET integration guide](./02-dotnet-integration.md)
- **Protocol Details:** [OpenTelemetry fundamentals](./04-opentelemetry-fundamentals.md)
