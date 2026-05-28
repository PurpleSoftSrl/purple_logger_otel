# purple_logger_otel

OpenTelemetry bridge for [purple_logger](https://pub.dev/packages/purple_logger) — routes structured log events to OTLP via [dartastic_opentelemetry](https://pub.dev/packages/dartastic_opentelemetry).

## Features

- **Zero-friction bridge** — Drop-in `OtelLoggerProvider` in the purple_logger pipeline
- **Full severity mapping** — PurpleLogLevel → OTel SeverityNumber (1–21)
- **Structured attributes** — Properties, scope, error, and stack trace all become OTel attributes
- **Trace correlation** — Auto-extracts `traceId`/`spanId` from the current OTel context
- **OTLP export** — gRPC and HTTP exporters via dartastic_opentelemetry
- **Batch processing** — Production-ready `BatchLogRecordProcessor` with configurable queue

## Quick start

```dart
import 'package:purple_logger/purple_logger.dart';
import 'package:purple_logger_otel/purple_logger_otel.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

void main() async {
  // 1. Initialize OTel SDK
  await OTel.initialize(
    serviceName: 'my-service',
    endpoint: 'http://localhost:4318',
  );

  // 2. Add OTel processor (batch for production)
  OTel.loggerProvider().addLogRecordProcessor(
    BatchLogRecordProcessor(
      OtlpHttpLogRecordExporter(
        OtlpHttpLogRecordExporterConfig(endpoint: 'http://collector:4318'),
      ),
    ),
  );

  // 3. Use OtelLoggerProvider in the purple_logger pipeline
  final factory = LoggingBuilder()
    .addProvider(OtelLoggerProvider(otelProvider: OTel.loggerProvider()))
    .addConsole()
    .build();

  final logger = factory.createLogger('MyApp');
  logger.info('Hello OTel!', properties: {'userId': 42});

  factory.dispose();
}
```

## Severity mapping

| PurpleLogLevel | OTel SeverityNumber | OTel SeverityText |
|----------------|--------------------:|-------------------|
| trace          | 1                   | TRACE             |
| debug          | 5                   | DEBUG             |
| info           | 9                   | INFO              |
| warning       | 13                  | WARN              |
| error         | 17                  | ERROR             |
| fatal         | 21                  | FATAL             |
| none          | 0                   | (suppressed)      |

## Attribute mapping

Every `LogEvent` is converted to an OTel log record with:

| Source | OTel Attribute Key |
|--------|-------------------|
| `properties` | Direct key-value mapping |
| `LoggingScope` properties | Merged into attributes |
| `error` | `error.type`, `error.message` |
| `stackTrace` | `error.stackTrace` |
| Active span | `traceId`, `spanId` |

## License

Apache-2.0