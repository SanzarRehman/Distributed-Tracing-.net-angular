# Pathfinder — Distributed Tracing Demo

A full-stack demo showing OpenTelemetry distributed tracing across Angular frontends and a .NET backend.

## Architecture

```
┌─────────────────────┐   ┌─────────────────────┐
│  Angular UI (Zone)  │   │ Angular UI (Zoneless)│
│  :4200              │   │  :4201               │
└────────┬────────────┘   └────────┬─────────────┘
         │ HTTP + Trace Context    │
         └────────────┬────────────┘
                      ▼
            ┌──────────────────┐
            │  .NET API :5215  │
            │  (Auto-Instrumented)
            └────────┬─────────┘
                     │ OTLP (gRPC)
                     ▼
          ┌────────────────────┐
          │  OTel Collector    │───→ Jaeger :16686
          │  :4319 (gRPC)      │───→ Your Custom Service
          │  :4320 (HTTP)      │───→ Honeycomb / Datadog / etc.
          └────────────────────┘
```

## Quick Start

### Prerequisites
- [Docker](https://docs.docker.com/get-docker/) & [Docker Compose](https://docs.docker.com/compose/install/)

### Run Everything (One Command)

```bash
docker compose up -d
```

This starts **5 services**:

| Service | URL | Description |
|---------|-----|-------------|
| **Jaeger UI** | http://localhost:16686 | View traces |
| **Angular UI (Zone)** | http://localhost:4200 | Standard Angular app |
| **Angular UI (Zoneless)** | http://localhost:4201 | Zoneless Angular app |
| **.NET API** | http://localhost:5215/api/health | Backend API (auto-instrumented) |
| **OTel Collector** | localhost:4319 (gRPC) | Trace routing & fan-out |

### Verify It Works

1. Open http://localhost:4200 (or :4201)
2. Click any action button (e.g., "Health Check")
3. Open http://localhost:16686 → Select `pathfinder-api` → **Find Traces**
4. You should see end-to-end traces: `Browser → API`

## Sending Traces to Your Custom Service

Edit `otel-collector-config.yaml` and uncomment the custom exporter:

```yaml
exporters:
  otlp/custom:
    endpoint: https://ingest.yourproduct.com:443
    headers:
      Authorization: "Bearer YOUR_API_KEY"

service:
  pipelines:
    traces:
      exporters:
        - otlp/jaeger
        - otlp/custom      # ← Add your exporter here
```

Then restart the collector:

```bash
docker compose restart otel-collector
```

**No app code changes needed!** The Collector handles all routing.

## Project Structure

```
pathfinder/
├── PathfinderApi/              # .NET 9 Backend (Auto-Instrumented)
│   ├── Dockerfile              #   Docker build with OTel CLR profiler
│   ├── Program.cs              #   Zero OTel code
│   └── run-with-otel.sh        #   Local dev script
├── pathfinder-ui/              # Angular UI (with Zone.js)
│   └── Dockerfile
├── pathfinder-ui-zoneless/     # Angular UI (Zoneless)
│   └── Dockerfile
├── docker-compose.yml          # All services
├── otel-collector-config.yaml  # Trace routing config
├── aws/                        # AWS ECS task definitions
├── azure/                      # Azure Container App configs
├── k8s/                        # Kubernetes manifests
└── docs/                       # Documentation
```

## Useful Commands

```bash
# Start all services
docker compose up -d

# Start only specific services
docker compose up -d jaeger pathfinder-api

# View API logs
docker logs -f pathfinder-api

# View Collector logs (see incoming traces)
docker logs -f pathfinder-otel-collector

# Rebuild after code changes
docker compose build pathfinder-api
docker compose up -d pathfinder-api

# Stop everything
docker compose down
```

## Documentation

See [docs/README.md](docs/README.md) for comprehensive guides on:
- Angular OTel integration
- .NET auto-instrumentation
- AWS, Azure, and Kubernetes deployment
