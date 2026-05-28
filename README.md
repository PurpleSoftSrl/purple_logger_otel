# purple_logger_otel

**Vendor-neutral** OpenTelemetry abstractions for [purple_logger](https://pub.dev/packages/purple_logger).

This package provides the **abstract interfaces** and **utility functions** for bridging purple_logger to OpenTelemetry — with **zero dependencies** on any specific OTel SDK.

For the concrete implementation using `dartastic_opentelemetry`, see [`purple_logger_otel_dartastic`](../purple_logger_otel_dartastic).

## Why a separate package?

Following the same pattern as Dart's `http` / `cupertino_http` / `http2_client`:

| Package | Purpose | OTel SDK dependency |
|---------|---------|-------------------|
| `purple_logger_otel` | Abstract interfaces + severity mapping | **None** |
| `purple_logger_otel_dartastic` | Concrete bridge using dartastic | `dartastic_opentelemetry` |

This means:
- **No lock-in** — swap OTel SDKs by creating a new implementation package
- **Zero-cost abstraction** — the interface layer adds no runtime overhead
- **Testable** — test against the abstractions, mock the SDK

## What's included

- `OtelLoggerProvider` — abstract provider that bridges to an OTel SDK
- `OtelLogger` — abstract logger with built-in property merging, error attachment, and severity mapping
- `OtelSeverityMapping` — mixin with standard PurpleLogLevel → OTel mapping
- `TraceContext` — value object for traceId/spanId correlation
- `severityNumber()` / `severityText()` — standalone mapping functions

## Architecture

```
purple_logger (core, zero deps)
    └── purple_logger_otel (abstractions, zero OTel deps)
            └── purple_logger_otel_dartastic (concrete, depends on dartastic)
```

## Usage

```dart
import 'package:purple_logger/purple_logger.dart';
import 'package:purple_logger_otel/purple_logger_otel.dart';
// Plus a concrete implementation:
import 'package:purple_logger_otel_dartastic/purple_logger_otel_dartastic.dart';

final factory = LoggingBuilder()
  .addProvider(DartasticOtelLoggerProvider(
    otelProvider: OTel.loggerProvider(),
  ))
  .addConsole()
  .build();
```

## Creating a custom bridge

Implement `OtelLoggerProvider` and `OtelLogger`:

```dart
final class MyOtelProvider extends OtelLoggerProvider {
  @override
  OtelLogger createOtelLogger(String category) =>
      MyOtelLogger(category: category);
}

final class MyOtelLogger implements OtelLogger, OtelSeverityMapping {
  @override
  final String category;

  MyOtelLogger({required this.category});

  @override
  void emitToOtel({
    required int severityNumber,
    required String severityText,
    required String body,
    required Map<String, Object> attributes,
  }) {
    // Send to your OTel SDK here
  }

  @override
  TraceContext extractTraceContext() => TraceContext.empty;

  // ... implement remaining Logger methods
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

## License

Apache-2.0