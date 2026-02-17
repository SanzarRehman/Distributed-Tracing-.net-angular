# .NET + OpenTelemetry Integration Guide

Complete guide for adding distributed tracing to any .NET application.

---

## Prerequisites

- .NET 6+ (tested with .NET 9)
- OpenTelemetry collector or Jaeger with OTLP endpoint

---

## 1. Install NuGet Packages

```bash
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
dotnet add package OpenTelemetry.Extensions.Hosting
dotnet add package OpenTelemetry.Instrumentation.AspNetCore
dotnet add package OpenTelemetry.Instrumentation.Http

# Optional: Structured logging with TraceId correlation
dotnet add package Serilog.AspNetCore
dotnet add package Serilog.Sinks.Console
dotnet add package Serilog.Enrichers.Span  # May not work in .NET 9
```

---

## 2. Configure OpenTelemetry in `Program.cs`

**`Program.cs`** (Minimal API / .NET 6+)

```csharp
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Serilog;
using System.Diagnostics;

var builder = WebApplication.CreateBuilder(args);

// 1. Configure OpenTelemetry Tracing
builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource
        .AddService("my-dotnet-api"))  // ⬅️ Change this to your service name
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()     // Auto-instrument ASP.NET Core
        .AddHttpClientInstrumentation()     // Auto-instrument HttpClient
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri("http://localhost:4317");  // ⬅️ Jaeger OTLP gRPC
            options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
        }));

// 2. Configure Serilog with TraceId enrichment (optional)
builder.Host.UseSerilog((context, config) =>
{
    config
        .Enrich.FromLogContext()
        .Enrich.With(new ActivityEnricher())  // Custom enricher (see below)
        .WriteTo.Console(outputTemplate:
            "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj} | TraceId:{TraceId} SpanId:{SpanId}{NewLine}{Exception}");
});

builder.Services.AddControllers();

var app = builder.Build();

// 3. Global exception handler middleware
app.Use(async (context, next) =>
{
    try
    {
        await next();
    }
    catch (Exception ex)
    {
        var activity = Activity.Current;
        activity?.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection
        {
            { "exception.type", ex.GetType().FullName },
            { "exception.message", ex.Message },
            { "exception.stacktrace", ex.StackTrace ?? "" }
        }));
        activity?.SetStatus(ActivityStatusCode.Error, ex.Message);

        context.Response.StatusCode = 500;
        await context.Response.WriteAsJsonAsync(new
        {
            error = ex.Message,
            traceId = activity?.TraceId.ToString() ?? "N/A"
        });
    }
});

app.MapControllers();
app.Run();
```

---

## 3. Create Custom Serilog Enricher

**`.NET 9 note:** `Serilog.Enrichers.Span` (`WithSpan()`) is deprecated. Use a custom enricher instead.

**`ActivityEnricher.cs`**

```csharp
using Serilog.Core;
using Serilog.Events;
using System.Diagnostics;

public class ActivityEnricher : ILogEventEnricher
{
    public void Enrich(LogEvent logEvent, ILogEventPropertyFactory propertyFactory)
    {
        var activity = Activity.Current;
        if (activity != null)
        {
            logEvent.AddPropertyIfAbsent(propertyFactory.CreateProperty("TraceId", activity.TraceId));
            logEvent.AddPropertyIfAbsent(propertyFactory.CreateProperty("SpanId", activity.SpanId));
        }
    }
}
```

---

## 4. Create Manual Spans

Use `ActivitySource` for operations not auto-instrumented.

**`MyService.cs`**

```csharp
using System.Diagnostics;

public class MyService
{
    private static readonly ActivitySource ActivitySource = new("my-dotnet-api");

    public async Task<string> PerformComplexOperation()
    {
        using var activity = ActivitySource.StartActivity("complex-operation");
        activity?.SetTag("user.id", "12345");

        try
        {
            // Your logic here
            await Task.Delay(100);  // Simulated work
            var result = "Success";

            activity?.SetStatus(ActivityStatusCode.Ok);
            return result;
        }
        catch (Exception ex)
        {
            activity?.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection
            {
                { "exception.type", ex.GetType().FullName },
                { "exception.message", ex.Message },
                { "exception.stacktrace", ex.StackTrace ?? "" }
            }));
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            throw;
        }
    }
}
```

**Register `ActivitySource` in `Program.cs`:**

```csharp
.WithTracing(tracing => tracing
    .AddAspNetCoreInstrumentation()
    .AddHttpClientInstrumentation()
    .AddSource("my-dotnet-api")  // ⬅️ Add this line
    .AddOtlpExporter(options => { ... }));
```

---

## 5. Controller Example with TraceId

**`HealthController.cs`**

```csharp
using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;

[ApiController]
[Route("api/[controller]")]
public class HealthController : ControllerBase
{
    [HttpGet]
    public IActionResult Get()
    {
        var activity = Activity.Current;
        var traceId = activity?.TraceId.ToString() ?? "N/A";

        return Ok(new
        {
            status = "healthy",
            timestamp = DateTime.UtcNow,
            traceId
        });
    }
}
```

---

## 6. Exception Recording (`.NET 9+`)

**Obsolete:** `activity?.RecordException(ex);`

**New approach:** Use `AddEvent` with exception tags:

```csharp
activity?.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection
{
    { "exception.type", ex.GetType().FullName },
    { "exception.message", ex.Message },
    { "exception.stacktrace", ex.StackTrace ?? "" }
}));
activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
```

---

## 7. Verify Traces

1. **Start Jaeger:** `docker compose up -d`
2. **Run .NET API:** `dotnet run`
3. **Make a request:** `curl http://localhost:5215/api/health`
4. **Open Jaeger UI:** http://localhost:16686
5. **Select service:** `my-dotnet-api`
6. **Verify TraceId** appears in:
   - Jaeger span
   - Console logs
   - HTTP response JSON

---

## Configuration Reference

| Option | Description | Default |
|--------|-------------|---------|
| `AddService(name)` | Service name in Jaeger | `unknown_service` |
| `Endpoint` | OTLP endpoint (gRPC or HTTP) | `http://localhost:4317` |
| `Protocol` | `Grpc` or `HttpProtobuf` | `Grpc` |
| `AddAspNetCoreInstrumentation` | Auto-instrument ASP.NET Core | - |
| `AddHttpClientInstrumentation` | Auto-instrument `HttpClient` | - |
| `AddSource(name)` | Register custom `ActivitySource` | - |

---

## CORS for .NET API (if calling from browser)

**`Program.cs`**

```csharp
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.WithOrigins("http://localhost:4200")  // Angular dev server
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

var app = builder.Build();
app.UseCors();  // ⬅️ Add before UseAuthorization
```

---

## Troubleshooting

### No Traces in Jaeger

1. **Check Jaeger is running:** `docker ps`
2. **Verify OTLP port:** `4317` (gRPC) or `4318` (HTTP)
3. **Check console logs** for OTLP export errors
4. **Test endpoint:** `curl http://localhost:4317` (should connect)

### TraceId Not in Logs

- **Ensure `ActivityEnricher` is registered** in Serilog config
- **Check `Activity.Current` is not null** during logging

### Serilog `WithSpan()` Not Found

- **In .NET 9+:** Use custom `ActivityEnricher` instead
- **Remove:** `Serilog.Enrichers.Span` package

---

## Next Steps

- **Angular Integration:** [Add frontend tracing](./01-angular-integration.md)
- **Advanced:** [Sampling, filtering, custom processors](./03-advanced-configuration.md)
- **Protocol Details:** [OpenTelemetry fundamentals](./04-opentelemetry-fundamentals.md)
