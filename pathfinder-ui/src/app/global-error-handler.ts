import { ErrorHandler, Injectable } from '@angular/core';
import { trace, SpanStatusCode } from '@opentelemetry/api';

@Injectable()
export class GlobalErrorHandler implements ErrorHandler {
    private tracer = trace.getTracer('pathfinder-ui');

    constructor() {
        // Catch unhandled promise rejections globally
        window.addEventListener('unhandledrejection', (event: PromiseRejectionEvent) => {
            const error = event.reason;
            const span = this.tracer.startSpan('unhandled-promise-rejection');
            span.setStatus({
                code: SpanStatusCode.ERROR,
                message: error?.message || String(error),
            });
            if (error instanceof Error) {
                span.recordException(error);
            }
            span.end();
            // Let it show in console naturally (don't preventDefault)
        });

        // Catch resource load failures (images, scripts, etc.)
        window.addEventListener('error', (event: ErrorEvent) => {
            const target = event.target as HTMLElement;
            // Only handle resource load errors (img, script, link)
            if (target && target !== window as any && (target.tagName === 'IMG' || target.tagName === 'SCRIPT' || target.tagName === 'LINK')) {
                const span = this.tracer.startSpan('resource-load-failure');
                span.setAttribute('resource.type', target.tagName.toLowerCase());
                span.setAttribute('resource.src', (target as any).src || (target as any).href || 'unknown');
                span.setStatus({
                    code: SpanStatusCode.ERROR,
                    message: `Failed to load ${target.tagName.toLowerCase()}: ${(target as any).src || (target as any).href}`,
                });
                span.end();
            }
        }, true); // capture phase to catch resource errors
    }

    // Catches all uncaught exceptions from Angular zone
    handleError(error: any): void {
        const span = this.tracer.startSpan('uncaught-error');
        span.setStatus({
            code: SpanStatusCode.ERROR,
            message: error.message || 'Unknown error',
        });
        span.recordException(error);
        span.end();

        // Show error in browser console naturally
        setTimeout(() => { throw error; });
    }
}
