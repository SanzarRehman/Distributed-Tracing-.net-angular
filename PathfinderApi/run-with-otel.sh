#!/bin/bash
# Run PathfinderApi locally with OpenTelemetry Auto-Instrumentation
# Usage: ./run-with-otel.sh
#
# Prerequisites:
#   1. Install the auto-instrumentation:
#      curl -sSfL https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/download/v1.12.0/otel-dotnet-auto-install.sh -o otel-install.sh
#      OTEL_DOTNET_AUTO_HOME="$HOME/.otel-dotnet-auto" sh otel-install.sh
#
#   2. Start Jaeger: docker compose up -d jaeger

set -e

OTEL_DOTNET_AUTO_HOME="${OTEL_DOTNET_AUTO_HOME:-$HOME/.otel-dotnet-auto}"

if [ ! -d "$OTEL_DOTNET_AUTO_HOME" ]; then
  echo "⚠️  OTel auto-instrumentation not found at $OTEL_DOTNET_AUTO_HOME"
  echo "   Installing now..."

  # Detect architecture
  if [[ "$(uname -m)" == "arm64" ]]; then
    export ARCHITECTURE="arm64"
  else
    export ARCHITECTURE="x64"
  fi

  # Detect OS
  if [[ "$OSTYPE" == "darwin"* ]]; then
    export OS_TYPE="macos"
  else
    export OS_TYPE="linux-glibc"
  fi

  curl -sSfL https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/download/v1.12.0/otel-dotnet-auto-install.sh -o /tmp/otel-install.sh
  sh /tmp/otel-install.sh
  rm /tmp/otel-install.sh
  echo "✅ Installed to $OTEL_DOTNET_AUTO_HOME"
fi

# Detect OS for profiler path
if [[ "$OSTYPE" == "darwin"* ]]; then
  PROFILER_PATH="$OTEL_DOTNET_AUTO_HOME/osx-x64/OpenTelemetry.AutoInstrumentation.Native.dylib"
  # Apple Silicon
  if [[ "$(uname -m)" == "arm64" ]]; then
    PROFILER_PATH="$OTEL_DOTNET_AUTO_HOME/osx-arm64/OpenTelemetry.AutoInstrumentation.Native.dylib"
  fi
else
  PROFILER_PATH="$OTEL_DOTNET_AUTO_HOME/linux-x64/OpenTelemetry.AutoInstrumentation.Native.so"
fi

# CLR Profiler + Startup Hooks (no AdditionalDeps — avoids .NET 9 version mismatch)
export CORECLR_ENABLE_PROFILING=1
export CORECLR_PROFILER="{918728DD-259F-4A6A-AC2B-B85E1B658318}"
export CORECLR_PROFILER_PATH="$PROFILER_PATH"
export DOTNET_STARTUP_HOOKS="$OTEL_DOTNET_AUTO_HOME/net/OpenTelemetry.AutoInstrumentation.StartupHook.dll"
export OTEL_DOTNET_AUTO_HOME

# OTel Configuration
export OTEL_SERVICE_NAME="pathfinder-api"
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4317"
export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
export OTEL_TRACES_EXPORTER="otlp"
export OTEL_METRICS_EXPORTER="none"
export OTEL_LOGS_EXPORTER="none"

echo "🚀 Starting PathfinderApi with OpenTelemetry Auto-Instrumentation"
echo "   Service: $OTEL_SERVICE_NAME"
echo "   Exporter: $OTEL_EXPORTER_OTLP_ENDPOINT"
echo ""

dotnet run
