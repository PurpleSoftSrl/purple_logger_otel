## 1.0.0

- **Breaking**: Refactored to vendor-neutral abstractions (zero OTel SDK dependencies).
- `OtelLoggerProvider` — abstract provider (was concrete `dartastic`-dependent class).
- `OtelLogger` — abstract logger with built-in property merging, error attachment, and severity mapping.
- `OtelSeverityMapping` — mixin with standard PurpleLogLevel → OTel mapping.
- `TraceContext` — value object for traceId/spanId correlation.
- `severityNumber()` / `severityText()` — standalone mapping functions.
- Concrete dartastic implementation moved to `purple_logger_otel_dartastic`.