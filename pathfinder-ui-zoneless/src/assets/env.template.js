(function (window) {
    window.env = window.env || {};

    // Environment variables
    window.env.API_URL = '${API_URL}';
    window.env.OTEL_URL = '${OTEL_URL}';
})(this);
