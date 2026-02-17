# OpenTelemetry in .NET and Angular

## .NET: Two Instrumentation Approaches

### Option 1: Manual Instrumentation
- Add OpenTelemetry NuGet packages to your project
- Write initialization code to configure the SDK
- Provides full control over instrumentation scope

### Option 2: Auto-Instrumentation
- **No NuGet dependencies required**
- Operates at infrastructure level (Docker/configuration)
- Can be applied to any .NET application without code modifications
- Automatically creates spans and exports to collectors like Jaeger

**Exception Enrichment (Optional):**
To capture detailed stack traces, add this exception handler:

```csharp
app.Use(async (context, next) => {
    try {
        await next(context);
    } catch (Exception ex) {
        var activity = Activity.Current;
        activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
        activity?.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection {
            { "exception.type", ex.GetType().FullName },
            { "exception.message", ex.Message },
            { "exception.stacktrace", ex.StackTrace ?? "" }
        }));
        
        Log.Error(ex, "Unhandled exception on {Path}", context.Request.Path);
        context.Response.StatusCode = 500;
        await context.Response.WriteAsJsonAsync(new {
            error = ex.GetType().Name,
            message = ex.Message,
            traceId = activity?.TraceId.ToString()
        });
    }
});
```

**Result:** Auto-instrumentation provides spans and exports with zero code changes. The exception handler adds error details with 6 lines and no additional packages.

---

## Angular: Manual Implementation Required

Angular requires manual OpenTelemetry setup. Browsers lack native OpenTelemetry support.

### Required Components

| Component | Lines of Code | Required |
|-----------|---------------|----------|
| `tracing.ts` (OTel SDK configuration) | ~50 lines | Yes - contains browser SDK implementation |
| `import './tracing'` in `main.ts` | 1 line | Yes - initializes SDK |
| OpenTelemetry npm packages | ~10 packages | Yes - provides browser OTel functionality |

---

## Network Traffic Implications

When frontend OpenTelemetry is active, each API request generates two network calls:

1. `GET /api/health` - The actual API request
2. `POST /v1/traces` - Trace data export to Jaeger/Collector

---

## Frontend Instrumentation: Cost-Benefit Analysis

### Production Environments: Generally Not Recommended

| Consideration | Impact |
|---------------|--------|
| Network overhead | 1-5KB per trace export, increased latency |
| Bundle size | 200KB+ additional JavaScript |
| User bandwidth | Consumed for observability infrastructure |
| Privacy | Trace data includes URLs, timing, user behavior |
| Coverage | Backend traces typically provide 90% of required visibility |

### Development/Staging Environments: High Value

| Benefit | Value Proposition |
|---------|-------------------|
| End-to-end trace correlation | Complete visibility: Browser → API → Database |
| Client-side timing precision | Actual user wait time including network and rendering |
| Network failure detection | Visibility into requests that never reach backend |
| Error attribution | Definitive client-side vs server-side error classification |

---

## Summary

**.NET:** Auto-instrumentation enables comprehensive observability with minimal effort. Add the exception handler for stack trace capture.

**Angular:** Requires manual setup with measurable overhead. Recommended for non-production environments where end-to-end trace correlation provides diagnostic value.
