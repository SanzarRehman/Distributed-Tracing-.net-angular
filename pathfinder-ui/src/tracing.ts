import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { XMLHttpRequestInstrumentation } from '@opentelemetry/instrumentation-xml-http-request';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';
import { ZoneContextManager } from '@opentelemetry/context-zone';

const env = (window as any).env || {
  API_URL: 'http://localhost:5215',
  OTEL_URL: 'http://localhost:4318/v1/traces'
};

const resource = resourceFromAttributes({
  [ATTR_SERVICE_NAME]: 'pathfinder-ui',
});

const exporter = new OTLPTraceExporter({
  url: env.OTEL_URL,
});

const provider = new WebTracerProvider({
  resource,
  spanProcessors: [new BatchSpanProcessor(exporter)],
});

provider.register({
  contextManager: new ZoneContextManager(),
});

registerInstrumentations({
  instrumentations: [
    new FetchInstrumentation({
      propagateTraceHeaderCorsUrls: [
        new RegExp(env.API_URL + '.*')
      ],
      clearTimingResources: true,
    }),
    new XMLHttpRequestInstrumentation({
      propagateTraceHeaderCorsUrls: [
        new RegExp(env.API_URL + '.*')
      ],
    }),
  ],
});

console.log('[Pathfinder] OpenTelemetry tracing initialized');
