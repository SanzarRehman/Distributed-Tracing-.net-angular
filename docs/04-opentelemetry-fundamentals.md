# OpenTelemetry Fundamentals

Understanding the OTLP protocol, trace data model, and building custom collectors.

---

## 1. OTLP Protocol Overview

**OpenTelemetry Protocol (OTLP)** is the standard for exporting traces, metrics, and logs.

### Transport Options

| Transport | Port | Use Case |
|-----------|------|----------|
| **gRPC** | 4317 | Backend-to-collector (efficient, binary) |
| **HTTP** | 4318 | Browser-to-collector (CORS-friendly) |

### Endpoints

- **Traces:** `/v1/traces` (HTTP) or `opentelemetry.proto.collector.trace.v1.TraceService/Export` (gRPC)
- **Metrics:** `/v1/metrics`
- **Logs:** `/v1/logs`

---

## 2. Trace Data Model

### Trace Hierarchy

```
Trace (e.g., "User Login Request")
└── Span: GET /api/auth/login (frontend)
    ├── Span: POST /api/auth/login (backend)
    │   ├── Span: SELECT * FROM users (database)
    │   └── Span: Redis.get("session:123") (cache)
    └── Span: Render login page (frontend)
```

### Span Structure

| Field | Description | Example |
|-------|-------------|---------|
| **TraceId** | Unique ID for entire trace | `0c3e8e9971ce3da4aef56211b48c07ba` |
| **SpanId** | Unique ID for this span | `f3b1eadaee3ffcc6` |
| **ParentSpanId** | Parent span (for hierarchy) | `a4d5f7c2e9b1` |
| **Name** | Operation name | `GET /api/users` |
| **Kind** | Span type | `SERVER`, `CLIENT`, `INTERNAL` |
| **Status** | Outcome | `OK`, `ERROR` |
| **Attributes** | Key-value metadata | `http.method=GET`, `user.id=123` |
| **Events** | Timestamped logs | `exception`, `cache_hit` |
| **Links** | References to other spans | Async work, batch processing |

### Span Kinds

| Kind | Description | Example |
|------|-------------|---------|
| `SERVER` | Receives inbound request | ASP.NET Core controller |
| `CLIENT` | Makes outbound request | `HttpClient.GetAsync()` |
| `INTERNAL` | Internal operation | `CalculateTax()` |
| `PRODUCER` | Sends message to queue | RabbitMQ publish |
| `CONSUMER` | Receives message from queue | RabbitMQ consume |

---

## 3. OTLP Message Format (Protobuf)

### HTTP POST Example

**Endpoint:** `POST http://localhost:4318/v1/traces`

**Headers:**
```
Content-Type: application/x-protobuf
```

**Body (Protobuf schema):**

```protobuf
message ExportTraceServiceRequest {
  repeated ResourceSpans resource_spans = 1;
}

message ResourceSpans {
  Resource resource = 1;
  repeated ScopeSpans scope_spans = 2;
}

message ScopeSpans {
  InstrumentationScope scope = 1;
  repeated Span spans = 2;
}

message Span {
  bytes trace_id = 1;
  bytes span_id = 2;
  string name = 3;
  SpanKind kind = 4;
  fixed64 start_time_unix_nano = 5;
  fixed64 end_time_unix_nano = 6;
  repeated KeyValue attributes = 7;
  Status status = 9;
  repeated Event events = 11;
}
```

### JSON Alternative (HTTP only)

**Endpoint:** `POST http://localhost:4318/v1/traces`

**Headers:**
```
Content-Type: application/json
```

**Body:**
```json
{
  "resourceSpans": [
    {
      "resource": {
        "attributes": [
          { "key": "service.name", "value": { "stringValue": "my-service" } }
        ]
      },
      "scopeSpans": [
        {
          "scope": { "name": "my-tracer" },
          "spans": [
            {
              "traceId": "0c3e8e9971ce3da4aef56211b48c07ba",
              "spanId": "f3b1eadaee3ffcc6",
              "name": "GET /api/users",
              "kind": "SPAN_KIND_SERVER",
              "startTimeUnixNano": "1710000000000000000",
              "endTimeUnixNano": "1710000001000000000",
              "attributes": [
                { "key": "http.method", "value": { "stringValue": "GET" } }
              ],
              "status": { "code": "STATUS_CODE_OK" }
            }
          ]
        }
      ]
    }
  ]
}
```

---

## 4. Building a Custom Collector

### Use Case

Process traces **before** sending to Jaeger (e.g., filtering, enrichment, routing).

### Node.js Example (Express + OTLP)

```bash
npm install express body-parser protobufjs
```

**`custom-collector.js`**

```javascript
const express = require('express');
const bodyParser = require('body-parser');

const app = express();
app.use(bodyParser.raw({ type: 'application/x-protobuf', limit: '10mb' }));
app.use(bodyParser.json({ limit: '10mb' }));

app.post('/v1/traces', (req, res) => {
  console.log('[Collector] Received trace data');
  console.log('Content-Type:', req.get('Content-Type'));
  console.log('Body size:', req.body.length, 'bytes');

  // TODO: Parse Protobuf or JSON
  // TODO: Filter, enrich, or transform spans
  // TODO: Forward to Jaeger, database, or custom storage

  res.status(200).send();
});

app.listen(4318, () => {
  console.log('[Collector] Listening on http://localhost:4318');
});
```

### Parsing Protobuf (Node.js)

```bash
# Download official OTLP proto files
curl -O https://raw.githubusercontent.com/open-telemetry/opentelemetry-proto/main/opentelemetry/proto/collector/trace/v1/trace_service.proto
```

```javascript
const protobuf = require('protobufjs');

const root = protobuf.loadSync('trace_service.proto');
const ExportTraceServiceRequest = root.lookupType('opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest');

app.post('/v1/traces', (req, res) => {
  const message = ExportTraceServiceRequest.decode(req.body);
  const spans = message.resourceSpans[0]?.scopeSpans[0]?.spans || [];

  spans.forEach(span => {
    console.log(`Span: ${span.name}, TraceId: ${span.traceId.toString('hex')}`);
  });

  res.status(200).send();
});
```

---

## 5. Alternative Backends

### Jaeger (Default)

```yaml
services:
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"  # UI
      - "4318:4318"    # OTLP HTTP
    environment:
      - COLLECTOR_OTLP_ENABLED=true
```

### Grafana Tempo

```yaml
services:
  tempo:
    image: grafana/tempo:latest
    ports:
      - "4318:4318"  # OTLP HTTP
    volumes:
      - ./tempo.yaml:/etc/tempo.yaml
    command: ["-config.file=/etc/tempo.yaml"]
```

**`tempo.yaml`**

```yaml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        http:

storage:
  trace:
    backend: local
    local:
      path: /tmp/tempo/traces
```

### Zipkin

```yaml
services:
  zipkin:
    image: openzipkin/zipkin:latest
    ports:
      - "9411:9411"  # UI
      - "9411:9411"  # Zipkin HTTP (not OTLP)
```

**Note:** Zipkin requires a **conversion layer** or use `ZipkinExporter` instead of OTLP.

### Custom Database Storage

**Example: Store spans in MongoDB**

```javascript
const { MongoClient } = require('mongodb');
const client = new MongoClient('mongodb://localhost:27017');

app.post('/v1/traces', async (req, res) => {
  const message = ExportTraceServiceRequest.decode(req.body);
  const spans = message.resourceSpans[0]?.scopeSpans[0]?.spans || [];

  await client.db('telemetry').collection('spans').insertMany(
    spans.map(span => ({
      traceId: span.traceId.toString('hex'),
      spanId: span.spanId.toString('hex'),
      name: span.name,
      timestamp: new Date(Number(span.startTimeUnixNano) / 1000000),
      attributes: span.attributes,
    }))
  );

  res.status(200).send();
});
```

---

## 6. Trace Context Propagation

### W3C Trace Context (Default)

**Header:** `traceparent`

**Format:** `00-<trace-id>-<span-id>-<flags>`

**Example:**
```
traceparent: 00-0c3e8e9971ce3da4aef56211b48c07ba-f3b1eadaee3ffcc6-01
```

- `00` = version
- `0c3e8e...` = trace ID (32 hex chars)
- `f3b1ea...` = parent span ID (16 hex chars)
- `01` = sampled flag

### B3 Format (Zipkin)

**Headers:**
```
X-B3-TraceId: 0c3e8e9971ce3da4aef56211b48c07ba
X-B3-SpanId: f3b1eadaee3ffcc6
X-B3-Sampled: 1
```

### Jaeger Format (Legacy)

**Header:** `uber-trace-id`

**Format:** `<trace-id>:<span-id>:<parent-id>:<flags>`

---

## 7. CORS Configuration for OTLP

When sending traces from **browser to collector**, CORS must be enabled.

### Jaeger

```yaml
environment:
  - COLLECTOR_OTLP_HTTP_CORS_ALLOWED_ORIGINS=http://localhost:4200
  - COLLECTOR_OTLP_HTTP_CORS_ALLOWED_HEADERS=content-type
```

### Custom Collector (Node.js)

```javascript
const cors = require('cors');

app.use(cors({
  origin: 'http://localhost:4200',
  methods: ['POST', 'OPTIONS'],
  allowedHeaders: ['content-type'],
}));
```

---

## 8. Performance Considerations

### Batch Export

**Default:** Spans are batched before export (reduces network overhead).

**Angular:**
```typescript
new BatchSpanProcessor(exporter, {
  maxQueueSize: 2048,
  scheduledDelayMillis: 5000,  // Export every 5s
});
```

**.NET:**
```json
{
  "OpenTelemetry": {
    "BatchExportProcessor": {
      "ScheduledDelayMillis": 5000
    }
  }
}
```

### Compression (gRPC only)

**gRPC** supports automatic compression (Gzip).

**HTTP Protobuf** does not compress by default—use reverse proxy (nginx, Envoy) for compression.

### Network Timeouts

**Angular:**
```typescript
new OTLPTraceExporter({
  timeoutMillis: 10000,  // 10s timeout
});
```

**.NET:**
```csharp
.AddOtlpExporter(options => options.TimeoutMilliseconds = 10000);
```

---

## 9. Debugging OTLP Export

### Angular (Console Exporter)

```typescript
import { ConsoleSpanExporter } from '@opentelemetry/sdk-trace-base';

const provider = new WebTracerProvider({
  spanProcessors: [
    new BatchSpanProcessor(new ConsoleSpanExporter()),  // Print to console
  ],
});
```

### .NET (Console Exporter)

```csharp
.WithTracing(tracing => tracing
    .AddConsoleExporter());  // Print to console
```

### curl Test

```bash
# Test Jaeger OTLP endpoint
curl -v -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": { "attributes": [{ "key": "service.name", "value": { "stringValue": "test" } }] },
      "scopeSpans": [{
        "spans": [{
          "traceId": "0af7651916cd43dd8448eb211c80319c",
          "spanId": "b9c7c989f97918e1",
          "name": "test-span",
          "kind": "SPAN_KIND_INTERNAL",
          "startTimeUnixNano": "1710000000000000000",
          "endTimeUnixNano": "1710000001000000000"
        }]
      }]
    }]
  }'
```

---

## Summary

| Topic | Key Points |
|-------|-----------|
| **OTLP Transport** | gRPC (4317) for backend, HTTP (4318) for browser |
| **Trace Model** | TraceId → Spans → Attributes/Events |
| **Span Kinds** | `SERVER`, `CLIENT`, `INTERNAL`, `PRODUCER`, `CONSUMER` |
| **Protobuf** | Binary format for efficient transport |
| **Custom Collector** | Parse OTLP, filter/enrich, forward to backend |
| **Backends** | Jaeger, Grafana Tempo, Zipkin, custom DB |
| **Propagation** | W3C Trace Context (default), B3, Jaeger |
| **CORS** | Required for browser → collector (exact origin) |

---

## Next Steps

- **Angular Basics:** [Angular integration guide](./01-angular-integration.md)
- **.NET Basics:** [.NET integration guide](./02-dotnet-integration.md)
- **Advanced:** [Sampling, filtering, custom processors](./03-advanced-configuration.md)
