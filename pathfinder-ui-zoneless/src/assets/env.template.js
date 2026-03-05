(function (window) {
    window.env = window.env || {};

    // Environment variables
    window.env.API_URL = '${API_URL}';
    window.env.OTEL_URL = '${OTEL_URL}';
    window.env.JAEGER_URL = '${JAEGER_URL}';
})(this);
