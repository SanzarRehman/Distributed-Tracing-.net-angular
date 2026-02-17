# .NET Auto-Instrumentation (Zero Code)

OpenTelemetry Auto-Instrumentation adds tracing to any .NET application **without modifying source code**. It uses the CLR Profiler to intercept HTTP requests, database queries, and more at runtime.

## How It Works

```
Your .NET App (zero OTel code)
        ↓
CLR Profiler hooks in at startup (via env vars)
        ↓
Automatically creates Spans for:
  ✅ ASP.NET Core requests
  ✅ HttpClient outgoing calls
  ✅ Entity Framework / SQL
  ✅ gRPC, Redis, and more
        ↓
Exports via OTLP to Jaeger / your backend
```

## Docker Setup

The [Dockerfile](file:///Users/sanzar/pathfinder/PathfinderApi/Dockerfile) installs the auto-instrumentation agent and sets the CLR profiler environment variables:

```dockerfile
# Download auto-instrumentation
ARG OTEL_VERSION=1.12.0
RUN curl -sSfL https://...otel-dotnet-auto-install.sh | sh

# CLR Profiler (architecture-aware)
ENV CORECLR_ENABLE_PROFILING=1
ENV CORECLR_PROFILER={918728DD-259F-4A6A-AC2B-B85E1B658318}
ENV CORECLR_PROFILER_PATH=/otel-dotnet-auto/profiler.so  # symlink to correct arch
ENV DOTNET_ADDITIONAL_DEPS=/otel-dotnet-auto/AdditionalDeps
ENV DOTNET_SHARED_STORE=/otel-dotnet-auto/store
ENV DOTNET_STARTUP_HOOKS=/otel-dotnet-auto/net/OpenTelemetry.AutoInstrumentation.StartupHook.dll
```

The [docker-compose.yml](file:///Users/sanzar/pathfinder/docker-compose.yml) configures the destination:

```yaml
pathfinder-api:
  environment:
    - OTEL_SERVICE_NAME=pathfinder-api
    - OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4317
    - OTEL_EXPORTER_OTLP_PROTOCOL=grpc
    - OTEL_TRACES_EXPORTER=otlp
    - OTEL_METRICS_EXPORTER=none
    - OTEL_LOGS_EXPORTER=none
    - OTEL_DOTNET_AUTO_TRACES_ADDITIONAL_SOURCES=PathfinderApi
```

## Switching Destinations

To send traces somewhere other than Jaeger, **only change the endpoint**:

| Destination | `OTEL_EXPORTER_OTLP_ENDPOINT` |
|-------------|-------------------------------|
| Jaeger | `http://jaeger:4317` |
| Honeycomb | `https://api.honeycomb.io` |
| Grafana Tempo | `http://tempo:4317` |
| Datadog | `http://datadog-agent:4317` |
| Your Product | `https://ingest.yourproduct.com` |

## Local Development

Use [run-with-otel.sh](file:///Users/sanzar/pathfinder/PathfinderApi/run-with-otel.sh) to run locally with auto-instrumentation:

```bash
cd PathfinderApi
./run-with-otel.sh
```

> [!WARNING]
> Local macOS auto-instrumentation has limited .NET 9 support. For reliable local tracing, use the minimal-code approach (add OTel NuGet packages). Docker (Linux) works fully.

## Environment Variables Reference

| Variable | Purpose | Default |
|----------|---------|---------|
| `OTEL_SERVICE_NAME` | Service name in traces | `pathfinder-api` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Where to send traces | `http://localhost:4317` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` or `http/protobuf` | `grpc` |
| `OTEL_TRACES_EXPORTER` | Exporter type | `otlp` |
| `OTEL_METRICS_EXPORTER` | Metrics exporter (`none` to disable) | `otlp` |
| `OTEL_LOGS_EXPORTER` | Logs exporter (`none` to disable) | `otlp` |
| `OTEL_LOG_LEVEL` | Debug logging (`debug`, `info`) | `info` |
| `OTEL_DOTNET_AUTO_TRACES_ADDITIONAL_SOURCES` | Custom `ActivitySource` names to listen to | — |
| `OTEL_DOTNET_AUTO_LOG_DIRECTORY` | Log file location for debugging | — |

## Debugging

If traces aren't appearing, enable debug logging:

```yaml
environment:
  - OTEL_LOG_LEVEL=debug
  - OTEL_DOTNET_AUTO_LOG_DIRECTORY=/tmp/otel-logs
```

Then check logs inside the container:

```bash
docker exec <container> cat /tmp/otel-logs/*.log
```
