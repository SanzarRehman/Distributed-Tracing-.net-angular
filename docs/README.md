# Pathfinder — OpenTelemetry Documentation

Comprehensive guides for implementing distributed tracing with OpenTelemetry.

## Documentation Structure

### 1. [Angular Integration Guide](./01-angular-integration.md)
Step-by-step guide for adding OpenTelemetry to any Angular project:
- Package installation
- Tracing initialization
- Automatic instrumentation (HTTP, Fetch, XHR)
- Manual span creation
- Error tracking
- CORS configuration for OTLP exporters
- **Runtime Configuration** (Docker/K8s) for dynamic URLs

### 1b. [Zoneless Angular Integration Guide](./01b-angular-zoneless.md)
Specialized guide for Angular 18+ Zoneless applications:
- Removing Zone.js dependencies (`context-zone`)
- Configuring `provideExperimentalZonelessChangeDetection`
- Manual UI updates with `changeDetectorRef`
- Handling async callbacks without Zone.js

### 2. [.NET Integration Guide](./02-dotnet-integration.md)
Step-by-step guide for adding OpenTelemetry to any .NET project:
- NuGet package installation
- Service registration and configuration
- Automatic instrumentation (ASP.NET Core, HTTP Client, SQL)
- Manual span creation with `ActivitySource`
- Structured logging with TraceId correlation
- Exception tracking

### 2b. [.NET Auto-Instrumentation (Zero Code)](./03-dotnet-auto-instrumentation.md)
Zero-code tracing using the CLR Profiler:
- Docker setup with auto-instrumentation agent
- Environment variable reference
- Architecture detection (ARM64/x64)
- Local development with `run-with-otel.sh`
- Debugging tips

### 3. [Advanced Configuration](./03-advanced-configuration.md)
Filtering, sampling, and customization:
- **Sampling strategies** (always-on, probabilistic, rate-limiting)
- **Filtering traces** (by HTTP status, operation name, attributes)
- **Custom span processors** for pre-export modification
- **Resource attributes** (service name, version, environment)
- **Propagation formats** (W3C Trace Context, B3, Jaeger)
- **Performance tuning** (batch size, timeout, queue limits)

### 4. [Docker Deployment](./05-docker-deployment.md)
Production deployment with Docker and Docker Compose:
- Multi-stage Dockerfiles
- docker-compose.prod.yml with health checks
- HTTPS with SSL termination
- Scaling and resource limits

---

## Quick Start

1. **Run Jaeger with CORS enabled:**
   ```bash
   docker compose up -d
   ```

2. **Angular:** See [Angular Integration Guide](./01-angular-integration.md)

3. **.NET:** See [.NET Integration Guide](./02-dotnet-integration.md)

4. **View traces:** http://localhost:16686
