## 1.0.0

- Initial release.
- `OtelLoggerProvider` — drop-in provider for the purple_logger pipeline.
- `OtelLogger` — bridges `LogEvent` to OTel `emit()`.
- `severityNumber()` / `severityText()` — PurpleLogLevel → OTel mapping.
- `extractTraceContext()` — auto-extracts traceId/spanId from current OTel context.
- Resilient to OTel not being initialized (graceful fallback).