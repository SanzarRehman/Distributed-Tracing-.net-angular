#!/usr/bin/env bash
# =============================================================
# build-release.sh — Pathfinder Release Package Builder
# =============================================================
# Builds all Docker images, exports them as .tar files, and
# assembles a self-contained release package with:
#   - Per-image directories with README + env vars
#   - docker-compose.yml for local/single-server deployment
#   - Helm chart for EKS / Kubernetes deployment
#   - ECR + EKS deployment guide
#
# Usage:
#   ENV=dev ./build-release.sh [version]
#
# Examples:
#   ENV=dev     ./build-release.sh 1.0.0
#   ENV=staging ./build-release.sh 2.0.0
#   ENV=prod    ./build-release.sh
# =============================================================

set -e

# ── Config ────────────────────────────────────────────────────
ENV="${ENV:-dev}"
VERSION="${1:-$(date +%Y%m%d-%H%M)}"
APP_VERSION="${ENV}-${VERSION}"
PACKAGE_NAME="pathfinder-release-${APP_VERSION}"
OUT_DIR="./release/${PACKAGE_NAME}"

IMAGE_API="pathfinder/api:${APP_VERSION}"
IMAGE_UI="pathfinder/ui-zoneless:${APP_VERSION}"
IMAGE_NEWAPP="pathfinder/newapp:${APP_VERSION}"

# ── Colors ────────────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${BLUE}[build]${NC} $*"; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }

# ── Step 1: Build Docker Images ───────────────────────────────
log "Building Docker images for ${APP_VERSION}..."

log "  → pathfinder/api"
docker build -t "${IMAGE_API}" ./PathfinderApi

log "  → pathfinder/ui-zoneless"
docker build -t "${IMAGE_UI}" ./pathfinder-ui-zoneless

log "  → pathfinder/newapp"
docker build -t "${IMAGE_NEWAPP}" ./NewApp

ok "All images built."

# ── Step 2: Create release directory structure ────────────────
log "Creating release directory: ${OUT_DIR}"
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/images"
mkdir -p "${OUT_DIR}/helm/pathfinder/templates"
mkdir -p "${OUT_DIR}/docs"

# ── Step 3: Export images to tar ──────────────────────────────
log "Saving images to tar..."

docker save "${IMAGE_API}"    -o "${OUT_DIR}/images/pathfinder-api.tar"
docker save "${IMAGE_UI}"     -o "${OUT_DIR}/images/pathfinder-ui-zoneless.tar"
docker save "${IMAGE_NEWAPP}" -o "${OUT_DIR}/images/pathfinder-newapp.tar"

ok "Images exported."

# ── Step 4: Per-image READMEs ─────────────────────────────────
log "Writing per-image READMEs..."

# --- pathfinder-api ---
cat > "${OUT_DIR}/images/pathfinder-api.README.md" << 'IMG_API'
# pathfinder/api

**.NET 9 Backend API** — serves the Angular UI, calls NewApp, publishes to RabbitMQ.

## Image Details

| Property | Value |
|---|---|
| Base Image | `mcr.microsoft.com/dotnet/aspnet:9.0` |
| Internal Port | `8080` |
| Health Check | `GET /api/health` |
| OTel Auto-Instrumentation | Built-in (CLR Profiler) |

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `OTEL_SERVICE_NAME` | No | `pathfinder-api` | Service name in Jaeger traces |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | `http://otel-collector:4317` | OTel Collector gRPC endpoint |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | No | `grpc` | OTLP protocol |
| `OTEL_TRACES_EXPORTER` | No | `otlp` | Trace exporter type |
| `OTEL_METRICS_EXPORTER` | No | `none` | Metrics exporter |
| `OTEL_LOGS_EXPORTER` | No | `none` | Logs exporter |
| `CORS_ORIGINS` | No | `http://localhost:4200,http://localhost:4201` | Comma-separated allowed origins |
| `RABBITMQ_HOST` | No | `rabbitmq` | RabbitMQ hostname |
| `NEWAPP_URL` | No | `http://newapp:8080/api/newapp/process` | NewApp HTTP endpoint |

### Auto-Instrumentation (built into image)

| Library | Env Var | Default |
|---|---|---|
| ASP.NET Core | `OTEL_DOTNET_AUTO_TRACES_ASPNETCORE_INSTRUMENTATION_ENABLED` | `true` |
| HttpClient | `OTEL_DOTNET_AUTO_TRACES_HTTPCLIENT_INSTRUMENTATION_ENABLED` | `true` |
| SqlClient | `OTEL_DOTNET_AUTO_TRACES_SQLCLIENT_INSTRUMENTATION_ENABLED` | `true` |
| EF Core | `OTEL_DOTNET_AUTO_TRACES_ENTITYFRAMEWORKCORE_INSTRUMENTATION_ENABLED` | `true` |

## Load & Run

```bash
docker load -i pathfinder-api.tar
docker run -d -p 5215:8080 \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317 \
  -e RABBITMQ_HOST=rabbitmq \
  pathfinder/api:<tag>
```
IMG_API

# --- pathfinder-ui-zoneless ---
cat > "${OUT_DIR}/images/pathfinder-ui-zoneless.README.md" << 'IMG_UI'
# pathfinder/ui-zoneless

**Angular 19 Zoneless UI** — served via nginx, calls the API and sends browser traces to OTel Collector.

## Image Details

| Property | Value |
|---|---|
| Base Image | `nginx:alpine` |
| Internal Port | `80` |
| Runtime Config | `envsubst` injects env vars into `env.js` at startup |

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `API_URL` | **Yes** | — | Backend API URL (browser-reachable) |
| `OTEL_URL` | **Yes** | — | OTel Collector HTTP endpoint for browser traces |
| `JAEGER_URL` | No | `http://localhost:16686` | Jaeger UI URL (for "Open Jaeger" button) |

## Load & Run

```bash
docker load -i pathfinder-ui-zoneless.tar
docker run -d -p 4200:80 \
  -e API_URL=http://your-api-host:5215/api \
  -e OTEL_URL=http://your-otel-host:4320/v1/traces \
  -e JAEGER_URL=http://your-jaeger-host:16686 \
  pathfinder/ui-zoneless:<tag>
```
IMG_UI

# --- pathfinder-newapp ---
cat > "${OUT_DIR}/images/pathfinder-newapp.README.md" << 'IMG_NEWAPP'
# pathfinder/newapp

**.NET 9 Secondary Service** — receives HTTP calls from API and consumes RabbitMQ messages.

## Image Details

| Property | Value |
|---|---|
| Base Image | `mcr.microsoft.com/dotnet/aspnet:9.0` |
| Internal Port | `8080` |
| Health Check | `GET /api/health` |
| OTel Auto-Instrumentation | Built-in (CLR Profiler) |

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `OTEL_SERVICE_NAME` | No | `newapp` | Service name in Jaeger |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | `http://otel-collector:4317` | OTel Collector gRPC endpoint |
| `RABBITMQ_HOST` | No | `rabbitmq` | RabbitMQ hostname |

### Auto-Instrumentation (built into image)

| Library | Env Var | Default |
|---|---|---|
| ASP.NET Core | `OTEL_DOTNET_AUTO_TRACES_ASPNETCORE_INSTRUMENTATION_ENABLED` | `true` |
| HttpClient | `OTEL_DOTNET_AUTO_TRACES_HTTPCLIENT_INSTRUMENTATION_ENABLED` | `true` |
| SqlClient | `OTEL_DOTNET_AUTO_TRACES_SQLCLIENT_INSTRUMENTATION_ENABLED` | `true` |

## Load & Run

```bash
docker load -i pathfinder-newapp.tar
docker run -d -p 8080:8080 \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317 \
  -e RABBITMQ_HOST=rabbitmq \
  pathfinder/newapp:<tag>
```
IMG_NEWAPP

ok "Per-image READMEs written."

# ── Step 5: Copy supporting files ─────────────────────────────
log "Copying configs..."

cp otel-collector-config.yaml "${OUT_DIR}/otel-collector-config.yaml"
cp .env.example              "${OUT_DIR}/.env.example"
cp OBSERVABILITY.md          "${OUT_DIR}/docs/OBSERVABILITY.md"

# ── Step 6: Write docker-compose.yml ──────────────────────────
log "Writing docker-compose.yml..."

cat > "${OUT_DIR}/docker-compose.yml" << COMPOSE
# Pathfinder — Release ${APP_VERSION}
# All ports/hosts configurable via .env

services:

  jaeger:
    image: jaegertracing/all-in-one:latest
    container_name: pathfinder-jaeger
    ports:
      - "\${JAEGER_PORT:-16686}:16686"
    environment:
      - COLLECTOR_OTLP_ENABLED=true
    restart: unless-stopped
    networks:
      - pathfinder-network
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:16686"]
      interval: 15s
      timeout: 5s
      retries: 5

  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    container_name: pathfinder-otel-collector
    volumes:
      - ./otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml
      - ./otel-data:/data
    ports:
      - "\${OTEL_COLLECTOR_GRPC_PORT:-4319}:4317"
      - "\${OTEL_COLLECTOR_HTTP_PORT:-4320}:4318"
    environment:
      - CUSTOM_CONSUMER_ENDPOINT=\${CUSTOM_CONSUMER_ENDPOINT}
    depends_on:
      jaeger:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - pathfinder-network

  pathfinder-api:
    image: ${IMAGE_API}
    container_name: pathfinder-api
    ports:
      - "\${API_PORT:-5215}:8080"
    environment:
      - OTEL_SERVICE_NAME=\${DOTNET_SERVICE_NAME:-pathfinder-api}
      - OTEL_EXPORTER_OTLP_ENDPOINT=\${OTEL_EXPORTER_OTLP_ENDPOINT:-http://otel-collector:4317}
      - OTEL_EXPORTER_OTLP_PROTOCOL=\${OTEL_EXPORTER_OTLP_PROTOCOL:-grpc}
      - OTEL_TRACES_EXPORTER=\${OTEL_TRACES_EXPORTER:-otlp}
      - OTEL_METRICS_EXPORTER=\${OTEL_METRICS_EXPORTER:-none}
      - OTEL_LOGS_EXPORTER=\${OTEL_LOGS_EXPORTER:-none}
      - OTEL_DOTNET_AUTO_TRACES_ADDITIONAL_SOURCES=PathfinderApi
      - OTEL_DOTNET_AUTO_TRACES_HTTPCLIENT_INSTRUMENTATION_ENABLED=true
      - OTEL_DOTNET_AUTO_TRACES_SQLCLIENT_INSTRUMENTATION_ENABLED=true
      - OTEL_DOTNET_AUTO_TRACES_ENTITYFRAMEWORKCORE_INSTRUMENTATION_ENABLED=true
      - OTEL_DOTNET_AUTO_TRACES_ASPNETCORE_INSTRUMENTATION_ENABLED=true
      - CORS_ORIGINS=\${CORS_ORIGINS:-http://localhost:4200,http://localhost:4201}
      - RABBITMQ_HOST=\${RABBITMQ_HOST:-rabbitmq}
      - NEWAPP_URL=\${NEWAPP_URL:-http://newapp:8080/api/newapp/process}
    depends_on:
      otel-collector:
        condition: service_started
    restart: unless-stopped
    networks:
      - pathfinder-network

  pathfinder-ui-zoneless:
    image: ${IMAGE_UI}
    container_name: pathfinder-ui-zoneless
    ports:
      - "\${UI_PORT:-4200}:80"
    environment:
      - API_URL=\${API_URL}
      - OTEL_URL=\${OTEL_COLLECTOR_HTTP_URL}
      - JAEGER_URL=\${JAEGER_URL:-http://localhost:16686}
    depends_on:
      - pathfinder-api
    restart: unless-stopped
    networks:
      - pathfinder-network

  rabbitmq:
    image: rabbitmq:3-management
    container_name: pathfinder-rabbitmq
    ports:
      - "\${RABBITMQ_AMQP_PORT:-5672}:5672"
      - "\${RABBITMQ_UI_PORT:-15672}:15672"
    restart: unless-stopped
    networks:
      - pathfinder-network

  newapp:
    image: ${IMAGE_NEWAPP}
    container_name: pathfinder-newapp
    ports:
      - "\${NEWAPP_PORT:-8080}:8080"
    environment:
      - OTEL_SERVICE_NAME=\${NEWAPP_SERVICE_NAME:-newapp}
      - OTEL_EXPORTER_OTLP_ENDPOINT=\${OTEL_EXPORTER_OTLP_ENDPOINT:-http://otel-collector:4317}
      - OTEL_EXPORTER_OTLP_PROTOCOL=\${OTEL_EXPORTER_OTLP_PROTOCOL:-grpc}
      - OTEL_TRACES_EXPORTER=\${OTEL_TRACES_EXPORTER:-otlp}
      - OTEL_METRICS_EXPORTER=\${OTEL_METRICS_EXPORTER:-none}
      - OTEL_LOGS_EXPORTER=\${OTEL_LOGS_EXPORTER:-none}
      - OTEL_DOTNET_AUTO_TRACES_ADDITIONAL_SOURCES=NewApp
      - OTEL_DOTNET_AUTO_TRACES_HTTPCLIENT_INSTRUMENTATION_ENABLED=true
      - OTEL_DOTNET_AUTO_TRACES_SQLCLIENT_INSTRUMENTATION_ENABLED=true
      - OTEL_DOTNET_AUTO_TRACES_ASPNETCORE_INSTRUMENTATION_ENABLED=true
      - RABBITMQ_HOST=\${RABBITMQ_HOST:-rabbitmq}
    depends_on:
      otel-collector:
        condition: service_started
    restart: unless-stopped
    networks:
      - pathfinder-network

networks:
  pathfinder-network:
    driver: bridge
COMPOSE

ok "docker-compose.yml written."

# ── Step 7: Write start.sh ────────────────────────────────────
log "Writing start.sh..."

cat > "${OUT_DIR}/start.sh" << 'STARTSH'
#!/usr/bin/env bash
set -e
GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[start]${NC} $*"; }
ok()  { echo -e "${GREEN}[ok]${NC} $*"; }

if [ ! -f ".env" ]; then
  echo "  ❌ No .env file found! Run: cp .env.example .env && nano .env"
  exit 1
fi

if [ -d "images" ] && [ "$(ls -A images/*.tar 2>/dev/null)" ]; then
  log "Loading Docker images..."
  for tar in images/*.tar; do
    log "  → $tar"
    docker load -i "$tar"
  done
  ok "Images loaded."
fi

log "Starting stack..."
docker compose up -d
echo ""
ok "Stack is up! See README.md for URLs."
echo ""
STARTSH

chmod +x "${OUT_DIR}/start.sh"
ok "start.sh written."

# ── Step 8: Write Helm Chart ──────────────────────────────────
log "Writing Helm chart..."

# Chart.yaml
cat > "${OUT_DIR}/helm/pathfinder/Chart.yaml" << HELMCHART
apiVersion: v2
name: pathfinder
description: Pathfinder Distributed Tracing Stack
type: application
version: ${VERSION}
appVersion: "${APP_VERSION}"
HELMCHART

# values.yaml
cat > "${OUT_DIR}/helm/pathfinder/values.yaml" << 'HELMVALUES'
# Pathfinder Helm Chart — values.yaml
# Override these in your environment-specific values file.

global:
  namespace: pathfinder

# ── Docker Registry ──────────────────────────────────────────
registry: ""  # e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com

# ── API ──────────────────────────────────────────────────────
api:
  image: pathfinder/api
  tag: latest
  replicas: 2
  port: 8080
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  env:
    OTEL_SERVICE_NAME: pathfinder-api
    OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
    OTEL_EXPORTER_OTLP_PROTOCOL: grpc
    OTEL_TRACES_EXPORTER: otlp
    OTEL_METRICS_EXPORTER: "none"
    OTEL_LOGS_EXPORTER: "none"
    OTEL_DOTNET_AUTO_TRACES_ADDITIONAL_SOURCES: PathfinderApi
    OTEL_DOTNET_AUTO_TRACES_HTTPCLIENT_INSTRUMENTATION_ENABLED: "true"
    OTEL_DOTNET_AUTO_TRACES_SQLCLIENT_INSTRUMENTATION_ENABLED: "true"
    OTEL_DOTNET_AUTO_TRACES_ENTITYFRAMEWORKCORE_INSTRUMENTATION_ENABLED: "true"
    OTEL_DOTNET_AUTO_TRACES_ASPNETCORE_INSTRUMENTATION_ENABLED: "true"
    CORS_ORIGINS: http://localhost:4200
    RABBITMQ_HOST: rabbitmq
    NEWAPP_URL: http://newapp:8080/api/newapp/process

# ── UI ───────────────────────────────────────────────────────
ui:
  image: pathfinder/ui-zoneless
  tag: latest
  replicas: 1
  port: 80
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi
  env:
    API_URL: http://api:8080/api
    OTEL_URL: http://otel-collector:4318/v1/traces
    JAEGER_URL: http://jaeger:16686

# ── NewApp ───────────────────────────────────────────────────
newapp:
  image: pathfinder/newapp
  tag: latest
  replicas: 1
  port: 8080
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 300m
      memory: 256Mi
  env:
    OTEL_SERVICE_NAME: newapp
    OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
    OTEL_EXPORTER_OTLP_PROTOCOL: grpc
    OTEL_TRACES_EXPORTER: otlp
    OTEL_METRICS_EXPORTER: "none"
    OTEL_LOGS_EXPORTER: "none"
    OTEL_DOTNET_AUTO_TRACES_ADDITIONAL_SOURCES: NewApp
    OTEL_DOTNET_AUTO_TRACES_HTTPCLIENT_INSTRUMENTATION_ENABLED: "true"
    OTEL_DOTNET_AUTO_TRACES_SQLCLIENT_INSTRUMENTATION_ENABLED: "true"
    OTEL_DOTNET_AUTO_TRACES_ASPNETCORE_INSTRUMENTATION_ENABLED: "true"
    RABBITMQ_HOST: rabbitmq

# ── RabbitMQ ─────────────────────────────────────────────────
rabbitmq:
  image: rabbitmq
  tag: 3-management
  port: 5672
  managementPort: 15672

# ── Jaeger ───────────────────────────────────────────────────
jaeger:
  image: jaegertracing/all-in-one
  tag: latest
  port: 16686

# ── OTel Collector ───────────────────────────────────────────
otelCollector:
  image: otel/opentelemetry-collector-contrib
  tag: latest
  grpcPort: 4317
  httpPort: 4318

# ── Ingress ──────────────────────────────────────────────────
ingress:
  enabled: true
  className: alb
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
  hosts:
    ui: pathfinder.example.com
    api: api.pathfinder.example.com
    jaeger: jaeger.pathfinder.example.com
HELMVALUES

# --- Templates ---

# Namespace
cat > "${OUT_DIR}/helm/pathfinder/templates/namespace.yaml" << 'HELMNS'
apiVersion: v1
kind: Namespace
metadata:
  name: {{ .Values.global.namespace }}
HELMNS

# ConfigMap
cat > "${OUT_DIR}/helm/pathfinder/templates/configmap.yaml" << 'HELMCM'
apiVersion: v1
kind: ConfigMap
metadata:
  name: pathfinder-config
  namespace: {{ .Values.global.namespace }}
data:
  {{- range $key, $val := .Values.api.env }}
  {{ $key }}: {{ $val | quote }}
  {{- end }}
HELMCM

# API Deployment + Service
cat > "${OUT_DIR}/helm/pathfinder/templates/api.yaml" << 'HELMAPI'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: {{ .Values.global.namespace }}
  labels:
    app: api
spec:
  replicas: {{ .Values.api.replicas }}
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: "{{ if .Values.registry }}{{ .Values.registry }}/{{ end }}{{ .Values.api.image }}:{{ .Values.api.tag }}"
        ports:
        - containerPort: {{ .Values.api.port }}
        env:
        {{- range $key, $val := .Values.api.env }}
        - name: {{ $key }}
          value: {{ $val | quote }}
        {{- end }}
        resources:
          {{- toYaml .Values.api.resources | nindent 10 }}
        livenessProbe:
          httpGet:
            path: /api/health
            port: {{ .Values.api.port }}
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/health
            port: {{ .Values.api.port }}
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: {{ .Values.global.namespace }}
spec:
  type: ClusterIP
  ports:
  - port: {{ .Values.api.port }}
    targetPort: {{ .Values.api.port }}
  selector:
    app: api
HELMAPI

# UI Deployment + Service
cat > "${OUT_DIR}/helm/pathfinder/templates/ui.yaml" << 'HELMUI'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ui
  namespace: {{ .Values.global.namespace }}
  labels:
    app: ui
spec:
  replicas: {{ .Values.ui.replicas }}
  selector:
    matchLabels:
      app: ui
  template:
    metadata:
      labels:
        app: ui
    spec:
      containers:
      - name: ui
        image: "{{ if .Values.registry }}{{ .Values.registry }}/{{ end }}{{ .Values.ui.image }}:{{ .Values.ui.tag }}"
        ports:
        - containerPort: {{ .Values.ui.port }}
        env:
        {{- range $key, $val := .Values.ui.env }}
        - name: {{ $key }}
          value: {{ $val | quote }}
        {{- end }}
        resources:
          {{- toYaml .Values.ui.resources | nindent 10 }}
---
apiVersion: v1
kind: Service
metadata:
  name: ui
  namespace: {{ .Values.global.namespace }}
spec:
  type: ClusterIP
  ports:
  - port: {{ .Values.ui.port }}
    targetPort: {{ .Values.ui.port }}
  selector:
    app: ui
HELMUI

# NewApp Deployment + Service
cat > "${OUT_DIR}/helm/pathfinder/templates/newapp.yaml" << 'HELMNEWAPP'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: newapp
  namespace: {{ .Values.global.namespace }}
  labels:
    app: newapp
spec:
  replicas: {{ .Values.newapp.replicas }}
  selector:
    matchLabels:
      app: newapp
  template:
    metadata:
      labels:
        app: newapp
    spec:
      containers:
      - name: newapp
        image: "{{ if .Values.registry }}{{ .Values.registry }}/{{ end }}{{ .Values.newapp.image }}:{{ .Values.newapp.tag }}"
        ports:
        - containerPort: {{ .Values.newapp.port }}
        env:
        {{- range $key, $val := .Values.newapp.env }}
        - name: {{ $key }}
          value: {{ $val | quote }}
        {{- end }}
        resources:
          {{- toYaml .Values.newapp.resources | nindent 10 }}
        livenessProbe:
          httpGet:
            path: /api/health
            port: {{ .Values.newapp.port }}
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: newapp
  namespace: {{ .Values.global.namespace }}
spec:
  type: ClusterIP
  ports:
  - port: {{ .Values.newapp.port }}
    targetPort: {{ .Values.newapp.port }}
  selector:
    app: newapp
HELMNEWAPP

# RabbitMQ
cat > "${OUT_DIR}/helm/pathfinder/templates/rabbitmq.yaml" << 'HELMRMQ'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq
  namespace: {{ .Values.global.namespace }}
  labels:
    app: rabbitmq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      containers:
      - name: rabbitmq
        image: "{{ .Values.rabbitmq.image }}:{{ .Values.rabbitmq.tag }}"
        ports:
        - containerPort: {{ .Values.rabbitmq.port }}
          name: amqp
        - containerPort: {{ .Values.rabbitmq.managementPort }}
          name: management
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
  namespace: {{ .Values.global.namespace }}
spec:
  type: ClusterIP
  ports:
  - port: {{ .Values.rabbitmq.port }}
    targetPort: {{ .Values.rabbitmq.port }}
    name: amqp
  - port: {{ .Values.rabbitmq.managementPort }}
    targetPort: {{ .Values.rabbitmq.managementPort }}
    name: management
  selector:
    app: rabbitmq
HELMRMQ

# Jaeger
cat > "${OUT_DIR}/helm/pathfinder/templates/jaeger.yaml" << 'HELMJAEGER'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: {{ .Values.global.namespace }}
  labels:
    app: jaeger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      containers:
      - name: jaeger
        image: "{{ .Values.jaeger.image }}:{{ .Values.jaeger.tag }}"
        ports:
        - containerPort: {{ .Values.jaeger.port }}
          name: ui
        - containerPort: 4317
          name: otlp-grpc
        env:
        - name: COLLECTOR_OTLP_ENABLED
          value: "true"
---
apiVersion: v1
kind: Service
metadata:
  name: jaeger
  namespace: {{ .Values.global.namespace }}
spec:
  type: ClusterIP
  ports:
  - port: {{ .Values.jaeger.port }}
    targetPort: {{ .Values.jaeger.port }}
    name: ui
  - port: 4317
    targetPort: 4317
    name: otlp-grpc
  selector:
    app: jaeger
HELMJAEGER

# OTel Collector
cat > "${OUT_DIR}/helm/pathfinder/templates/otel-collector.yaml" << 'HELMOTEL'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otel-collector
  namespace: {{ .Values.global.namespace }}
  labels:
    app: otel-collector
spec:
  replicas: 1
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      containers:
      - name: otel-collector
        image: "{{ .Values.otelCollector.image }}:{{ .Values.otelCollector.tag }}"
        ports:
        - containerPort: {{ .Values.otelCollector.grpcPort }}
          name: otlp-grpc
        - containerPort: {{ .Values.otelCollector.httpPort }}
          name: otlp-http
        volumeMounts:
        - name: config
          mountPath: /etc/otelcol-contrib/config.yaml
          subPath: config.yaml
      volumes:
      - name: config
        configMap:
          name: otel-collector-config
---
apiVersion: v1
kind: Service
metadata:
  name: otel-collector
  namespace: {{ .Values.global.namespace }}
spec:
  type: ClusterIP
  ports:
  - port: {{ .Values.otelCollector.grpcPort }}
    targetPort: {{ .Values.otelCollector.grpcPort }}
    name: otlp-grpc
  - port: {{ .Values.otelCollector.httpPort }}
    targetPort: {{ .Values.otelCollector.httpPort }}
    name: otlp-http
  selector:
    app: otel-collector
HELMOTEL

# Ingress
cat > "${OUT_DIR}/helm/pathfinder/templates/ingress.yaml" << 'HELMINGRESS'
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pathfinder-ingress
  namespace: {{ .Values.global.namespace }}
  annotations:
    {{- toYaml .Values.ingress.annotations | nindent 4 }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  rules:
  - host: {{ .Values.ingress.hosts.ui }}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ui
            port:
              number: {{ .Values.ui.port }}
  - host: {{ .Values.ingress.hosts.api }}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: {{ .Values.api.port }}
  - host: {{ .Values.ingress.hosts.jaeger }}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: jaeger
            port:
              number: {{ .Values.jaeger.port }}
{{- end }}
HELMINGRESS

ok "Helm chart written."

# ── Step 9: Write ECR + EKS Deployment Guide ─────────────────
log "Writing deployment guide..."

cat > "${OUT_DIR}/docs/ECR-EKS-GUIDE.md" << EKSGUIDE
# Pathfinder — ECR + EKS Deployment Guide

## Prerequisites

- AWS CLI configured (\`aws configure\`)
- \`kubectl\` connected to your EKS cluster
- \`helm\` v3+ installed
- ECR repositories created for each image

---

## Step 1: Create ECR Repositories

\`\`\`bash
aws ecr create-repository --repository-name pathfinder/api
aws ecr create-repository --repository-name pathfinder/ui-zoneless
aws ecr create-repository --repository-name pathfinder/newapp
\`\`\`

## Step 2: Load, Tag, and Push Images

\`\`\`bash
# Set your registry
ECR=\$(aws sts get-caller-identity --query Account --output text).dkr.ecr.\$(aws configure get region).amazonaws.com

# Login to ECR
aws ecr get-login-password | docker login --username AWS --password-stdin \$ECR

# Load images from tar
for tar in images/*.tar; do docker load -i "\$tar"; done

# Tag for ECR
docker tag pathfinder/api:${APP_VERSION}          \$ECR/pathfinder/api:${APP_VERSION}
docker tag pathfinder/ui-zoneless:${APP_VERSION}  \$ECR/pathfinder/ui-zoneless:${APP_VERSION}
docker tag pathfinder/newapp:${APP_VERSION}       \$ECR/pathfinder/newapp:${APP_VERSION}

# Push
docker push \$ECR/pathfinder/api:${APP_VERSION}
docker push \$ECR/pathfinder/ui-zoneless:${APP_VERSION}
docker push \$ECR/pathfinder/newapp:${APP_VERSION}
\`\`\`

## Step 3: Deploy with Helm

\`\`\`bash
# Create a values override for your environment
cat > values-prod.yaml << EOF
registry: \$ECR

api:
  tag: "${APP_VERSION}"
  env:
    CORS_ORIGINS: https://pathfinder.yourdomain.com
    RABBITMQ_HOST: rabbitmq
    NEWAPP_URL: http://newapp:8080/api/newapp/process
    OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317

ui:
  tag: "${APP_VERSION}"
  env:
    API_URL: https://api.yourdomain.com/api
    OTEL_URL: https://otel.yourdomain.com/v1/traces
    JAEGER_URL: https://jaeger.yourdomain.com

newapp:
  tag: "${APP_VERSION}"

ingress:
  enabled: true
  hosts:
    ui: pathfinder.yourdomain.com
    api: api.yourdomain.com
    jaeger: jaeger.yourdomain.com
EOF

# Install / upgrade
helm upgrade --install pathfinder ./helm/pathfinder \\
  -f values-prod.yaml \\
  -n pathfinder --create-namespace
\`\`\`

## Step 4: Verify

\`\`\`bash
kubectl get pods -n pathfinder
kubectl get svc -n pathfinder
kubectl get ingress -n pathfinder
\`\`\`

---

## Architecture on EKS

\`\`\`
                    ALB Ingress
                        │
         ┌──────────────┼──────────────┐
         │              │              │
    pathfinder.com  api.pathfinder  jaeger.pathfinder
         │              │              │
     ┌───┴───┐     ┌────┴────┐    ┌────┴────┐
     │  UI   │     │   API   │    │ Jaeger  │
     │ :80   │     │  :8080  │    │ :16686  │
     └───────┘     └────┬────┘    └─────────┘
                        │
              ┌─────────┼─────────┐
              │         │         │
         ┌────┴────┐ ┌──┴──┐ ┌───┴────────┐
         │ NewApp  │ │ RMQ │ │ OTel Coll. │
         │  :8080  │ │5672 │ │ 4317/4318  │
         └─────────┘ └─────┘ └────────────┘
\`\`\`

---

## Port Reference (Kubernetes Internal)

All services communicate via Kubernetes ClusterIP services.
No host port mapping needed — the Ingress handles external traffic.

| Service | ClusterIP Port | Protocol |
|---|---|---|
| api | 8080 | HTTP |
| ui | 80 | HTTP |
| newapp | 8080 | HTTP |
| rabbitmq | 5672 / 15672 | AMQP / HTTP |
| jaeger | 16686 / 4317 | HTTP / gRPC |
| otel-collector | 4317 / 4318 | gRPC / HTTP |
EKSGUIDE

ok "ECR + EKS guide written."

# ── Step 10: Write main README ────────────────────────────────
log "Writing README.md..."

cat > "${OUT_DIR}/README.md" << README
# Pathfinder — Release ${APP_VERSION}

## Package Contents

\`\`\`
${PACKAGE_NAME}/
├── images/
│   ├── pathfinder-api.tar              + pathfinder-api.README.md
│   ├── pathfinder-ui-zoneless.tar      + pathfinder-ui-zoneless.README.md
│   └── pathfinder-newapp.tar           + pathfinder-newapp.README.md
├── helm/pathfinder/                    Helm chart for EKS / K8s
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
├── docs/
│   ├── ECR-EKS-GUIDE.md               Full AWS deployment guide
│   └── OBSERVABILITY.md               Tracing architecture docs
├── docker-compose.yml                  Local / single-server deployment
├── otel-collector-config.yaml          OTel Collector config
├── .env.example                        Environment variable template
├── start.sh                            Quick-start script
└── README.md                           This file
\`\`\`

---

## Option A: Local / Single Server (docker-compose)

\`\`\`bash
cp .env.example .env && nano .env
./start.sh
\`\`\`

## Option B: AWS EKS (Helm)

See \`docs/ECR-EKS-GUIDE.md\` for the full walkthrough:
1. Push images to ECR
2. Create \`values-prod.yaml\` with your domain/registry
3. \`helm upgrade --install pathfinder ./helm/pathfinder -f values-prod.yaml\`

---

## Image Reference

| Image | Tag | Port | README |
|---|---|---|---|
| \`pathfinder/api\` | \`${APP_VERSION}\` | 8080 | \`images/pathfinder-api.README.md\` |
| \`pathfinder/ui-zoneless\` | \`${APP_VERSION}\` | 80 | \`images/pathfinder-ui-zoneless.README.md\` |
| \`pathfinder/newapp\` | \`${APP_VERSION}\` | 8080 | \`images/pathfinder-newapp.README.md\` |

Each image README contains the full environment variable reference.

---

## Quick Reference: All Environment Variables

See \`.env.example\` for the complete list with defaults.
See each image's README in \`images/\` for per-service details.
README

ok "README.md written."

# ── Step 11: Zip ──────────────────────────────────────────────
log "Zipping release package..."
cd release
zip -r "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}/"
cd ..

ZIPFILE="./release/${PACKAGE_NAME}.zip"
ZIPSIZE=$(du -sh "${ZIPFILE}" | cut -f1)

echo ""
ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "  Release package ready!"
ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  📦 ${ZIPFILE} (${ZIPSIZE})"
echo ""
echo "  Contents:"
echo "    images/     — 3 Docker image tars + per-image READMEs"
echo "    helm/       — Helm chart for EKS deployment"
echo "    docs/       — ECR/EKS guide + observability docs"
echo "    compose     — docker-compose.yml + .env.example + start.sh"
echo ""
warn "Public images (jaeger, rabbitmq, otel-collector) pulled from Docker Hub at runtime."
echo ""
