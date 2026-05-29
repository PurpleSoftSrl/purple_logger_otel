# purple_logger_otel

[![Pub Version](https://img.shields.io/pub/v/purple_logger_otel.svg)](https://pub.dev/packages/purple_logger_otel)
[![License](https://img.shields.io/badge/license-AGPL%203.0-blue.svg)](LICENSE)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.2.0-blue.svg)](https://dart.dev)

> **OpenTelemetry bridge abstractions for [purple_logger](https://pub.dev/packages/purple_logger) — define once, implement for any OTel backend.**

---

## Why this package exists

The OpenTelemetry ecosystem has multiple Dart SDKs (`dartastic_opentelemetry`, `open_telemetry`, custom vendor implementations, etc.). Without an abstraction layer, every package that wants to bridge purple_logger to OTel must commit to a specific SDK — coupling your logging pipeline to a single OTel backend.

**purple_logger_otel** solves this with **interface segregation**. It defines the contracts that every OTel bridge must implement, with **zero dependencies** on any OpenTelemetry SDK. Your application code depends only on these abstractions. When you need to swap the OTel backend (or evaluate different SDKs), you change one import — nothing else.

This follows the same architectural pattern as Dart's `http` / `cupertino_http` / `http2_client` split:

| Package | Role | OTel SDK dependency |
|---------|------|-------------------|
| `purple_logger_otel` | Abstract interfaces, severity mapping, trace context | **None** |
| `purple_logger_otel_dartastic` | Concrete bridge using `dartastic_opentelemetry` | `dartastic_opentelemetry` |
| _Your custom bridge_ | Concrete bridge for any OTel SDK you choose | Whatever you need |

---

## Architecture

```
                       purple_logger
                            │
                            │ (depends on)
                            ▼
                  purple_logger_otel      ← You write code against THIS layer
                   (abstractions)
                   zero OTel deps
                    ╱          ╲
                   ╱            ╲
    purple_logger_otel_dartastic   YourCustomOtelBridge  
    (dartastic_opentelemetry)      (any OTel SDK)
```

Your application only ever imports `purple_logger` and `purple_logger_otel`. The concrete bridge is an **implementation detail** swapped at the composition root.

---

## Interfaces

### `OtelLoggerProvider`

Abstract provider that extends purple_logger's `LoggerProvider`. Creates and caches `OtelLogger` instances by category name.

```dart
abstract class OtelLoggerProvider extends LoggerProvider {
  OtelLogger createOtelLogger(String category);   // Subclasses must implement
  @override
  Logger createLogger(String category);            // Caches & delegates
  @override
  void dispose();                                  // Clears cached loggers
}
```

**Responsibilities:**
- Factory for `OtelLogger` instances (one per category)
- Logger caching — repeated calls for the same category return the same instance
- Lifecycle management via `dispose()`

### `OtelLogger`

Abstract logger that bridges purple_logger log events to any OTel SDK. Implements purple_logger's `Logger` and the `OtelSeverityMapping` mixin.

```dart
abstract class OtelLogger implements Logger, OtelSeverityMapping {
  final String category;

  OtelLogger({required this.category});

  // Subclasses must implement:
  void emitToOtel({
    required int severityNumber,
    required String severityText,
    required String body,
    required Map<String, Object> attributes,
  });
  TraceContext extractTraceContext();

  // Pre-built: scope merging, error attachment, null filtering, severity mapping
  @override
  void log(PurpleLogLevel level, Object? message, {...});
  @override
  bool isEnabled(PurpleLogLevel level);
  @override
  LoggingScope beginScope(Map<String, Object?> properties);
}
```

**What `OtelLogger` does for free (no override needed):**
- Merges `LoggingScope.currentProperties` with caller-supplied properties
- Attaches `error.type`, `error.message`, and `error.stackTrace` when an error is provided
- Extracts trace context (traceId, spanId) for log-trace correlation
- Filters out null values from attributes (OTel cannot ingest nulls)
- Maps `PurpleLogLevel` to OTel severity via `severityNumber()` / `severityText()`

**What you must implement:**
- `emitToOtel()` — send the assembled log record to your OTel SDK
- `extractTraceContext()` — read the current traceId/spanId from your SDK's context

### `OtelSeverityMapping`

Mixin that provides the standard OTel severity mapping for `PurpleLogLevel`. Mix into any `OtelLogger` subclass to get `severityNumber()` and `severityText()` for free.

```dart
mixin OtelSeverityMapping {
  int severityNumber(PurpleLogLevel level);
  String severityText(PurpleLogLevel level);
}
```

You can also use the **standalone functions** directly without the mixin:

```dart
import 'package:purple_logger/purple_logger.dart';
import 'package:purple_logger_otel/purple_logger_otel.dart';

final num  = severityNumber(PurpleLogLevel.error);  // 17
final text = severityText(PurpleLogLevel.error);     // 'ERROR'
```

### `TraceContext`

Vendor-neutral value object for trace correlation. Carries the `traceId` and `spanId` extracted from the current OTel context.

```dart
final class TraceContext {
  final String? traceId;
  final String? spanId;
  bool get isValid => traceId != null && spanId != null;
  const TraceContext({this.traceId, this.spanId});
  static const TraceContext empty = TraceContext();
}
```

When a span is active (e.g. inside an OTel tracing scope), the concrete bridge populates this with the current trace and span IDs. These are automatically attached to emitted log records, enabling correlation between logs and traces in backends like Jaeger, Tempo, Grafana, or Azure Monitor.

If no span is active, `extractTraceContext()` returns `TraceContext.empty` and no trace fields are attached.

---

## Implementing a custom backend

To bridge purple_logger to a new OTel SDK, you need two classes and one function. This complete example uses a hypothetical `your_otel_sdk` package:

```dart
import 'package:your_otel_sdk/your_otel_sdk.dart';
import 'package:purple_logger/purple_logger.dart';
import 'package:purple_logger_otel/purple_logger_otel.dart';

// 1. The provider: creates logger instances and initializes the OTel SDK.
final class YourOtelLoggerProvider extends OtelLoggerProvider {
  final YourOtelSdk _sdk;

  YourOtelLoggerProvider(this._sdk);

  @override
  OtelLogger createOtelLogger(String category) =>
      _YourOtelLogger(category: category, sdk: _sdk);
}

// 2. The logger: mix in OtelSeverityMapping, implement the two abstract methods.
final class _YourOtelLogger implements OtelLogger, OtelSeverityMapping {
  @override
  final String category;

  final YourOtelSdk _sdk;

  _YourOtelLogger({required this.category, required YourOtelSdk sdk})
      : _sdk = sdk;

  @override
  void emitToOtel({
    required int severityNumber,
    required String severityText,
    required String body,
    required Map<String, Object> attributes,
  }) {
    _sdk.emitLogRecord(
      severityNumber: severityNumber,
      severityText: severityText,
      body: body,
      attributes: attributes,
    );
  }

  @override
  TraceContext extractTraceContext() {
    final span = _sdk.getActiveSpan();
    if (span == null) return TraceContext.empty;
    return TraceContext(
      traceId: span.traceId,
      spanId: span.spanId,
    );
  }

  // ── Convenience methods ──────────────────────────────────────────
  // Since your class implements Logger (via OtelLogger), you must also
  // provide the convenience methods that delegate to log(). Mix in
  // LoggerConvenience from purple_logger for this:
  @override
  void trace(Object? message, {Map<String, Object?>? properties}) =>
      log(PurpleLogLevel.trace, message, properties: properties);

  @override
  void debug(Object? message, {Map<String, Object?>? properties}) =>
      log(PurpleLogLevel.debug, message, properties: properties);

  @override
  void info(Object? message, {Map<String, Object?>? properties}) =>
      log(PurpleLogLevel.info, message, properties: properties);

  @override
  void warning(Object? message, {Map<String, Object?>? properties}) =>
      log(PurpleLogLevel.warning, message, properties: properties);

  @override
  void error(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? properties,
  }) =>
      log(PurpleLogLevel.error, message,
          properties: properties, error: error, stackTrace: stackTrace);

  @override
  void fatal(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? properties,
  }) =>
      log(PurpleLogLevel.fatal, message,
          properties: properties, error: error, stackTrace: stackTrace);

  @override
  void log(
    PurpleLogLevel level,
    Object? message, {
    Map<String, Object?>? properties,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Either implement log() yourself, or call super.log() with the
    // mixin logic from OtelSeverityMapping. The simplest path is to
    // override log() and replicate the OtelLogger base class logic
    // shown in the test file.
    super.log(level, message,
        properties: properties, error: error, stackTrace: stackTrace);
  }
}

// 3. Wire it up at startup:
void main() {
  final sdk = YourOtelSdk.initialize();
  final factory = LoggingBuilder()
      .addProvider(YourOtelLoggerProvider(sdk))
      .addConsole()
      .build();

  final logger = factory.createLogger('MyService');
  logger.info('Started', properties: {'version': '1.0.0'});
}
```

The only OTel-specific code lives in `emitToOtel()` and `extractTraceContext()`. Everything else — scope merging, error attachment, null filtering, severity mapping — is inherited from the base class.

---

## Severity mapping

Follows the [OpenTelemetry Logs Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/#mapping-severitynumber).

| `PurpleLogLevel` | OTel `SeverityNumber` | OTel `SeverityText` | Notes |
|:----------------|:---------------------|:--------------------|:------|
| `trace` | 1 (TRACE) | `TRACE` | Finest-grained diagnostics |
| `debug` | 5 (DEBUG) | `DEBUG` | Developer diagnostics |
| `info` | 9 (INFO) | `INFO` | Normal operational events |
| `warning` | 13 (WARN) | `WARN` | Recoverable anomalies |
| `error` | 17 (ERROR) | `ERROR` | Operation failures |
| `fatal` | 21 (FATAL) | `FATAL` | Unrecoverable, requires intervention |
| `none` | 0 (UNSPECIFIED) | `''` | Log event suppressed |

The mapping is available in three forms — use whichever fits your style:

```dart
// 1. As a mixin on any OtelLogger subclass
final class MyLogger implements OtelLogger, OtelSeverityMapping { ... }

// 2. As standalone functions
severityNumber(PurpleLogLevel.error);  // 17
severityText(PurpleLogLevel.error);    // 'ERROR'

// 3. Directly on PurpleLogLevel (built into purple_logger)
PurpleLogLevel.error.severityNumber;   // 17
PurpleLogLevel.error.severityText;     // 'ERROR'
```

---

## Installation

This package depends **only** on `purple_logger`. It does **not** pull in any OpenTelemetry SDK.

```yaml
# pubspec.yaml
dependencies:
  purple_logger: ^2.1.0
  purple_logger_otel: ^1.0.0
  # Choose one concrete bridge:
  purple_logger_otel_dartastic: ^1.0.0   # OR your custom bridge
```

Then import the abstractions:

```dart
import 'package:purple_logger/purple_logger.dart';
import 'package:purple_logger_otel/purple_logger_otel.dart';
```

---

## Companion packages

| Package | Description | pub.dev |
|---------|------------|---------|
| [`purple_logger`](https://pub.dev/packages/purple_logger) | Core structured logger with provider pipeline, zone scopes, file rotation | [![Pub](https://img.shields.io/pub/v/purple_logger.svg)](https://pub.dev/packages/purple_logger) |
| `purple_logger_otel` | **You are here** — abstractions, severity mapping, trace context | [![Pub](https://img.shields.io/pub/v/purple_logger_otel.svg)](https://pub.dev/packages/purple_logger_otel) |
| `purple_logger_otel_dartastic` | Concrete bridge using `dartastic_opentelemetry` | _(planned)_ |
| `purple_otel_sdk` | OTel SDK configuration, resource builders, batching exporters | _(planned)_ |

---

---




## Built by PurpleSoft

This package is developed and maintained by **[PurpleSoft S.r.l.](https://www.purplesoft.io)** — a software house with offices in Monza, Milano, and Lugano (Switzerland). Since 2017, we've been the team that companies call when the problem is too hard, too critical, or too late to fail.

### What makes us different

We don't build "yet another library." We build the infrastructure that other companies run their business on. When a Fortune 500 manufacturer needs to migrate their SAP ERP without downtime, they call us. When a bank needs distributed tracing that survives Black Friday traffic, they call us. When a startup needs an AI pipeline that runs on-device instead of in the cloud, they call us.

We write the code that runs on factory floors and in boardrooms. We ship Flutter apps that control physical payment terminals, deploy ONNX models to phones, build speech engines that understand Italian dialects, and design observability pipelines that catch production issues before customers notice.

### We don't just consult. We ship.

| What you need | What we deliver |
|---|---|
| OpenTelemetry at enterprise scale | Production-hardened SDK with 256 automated tests, red-team audited, zero crashes under edge cases |
| Flutter apps with custom native code | Platform-specific plugins for hardware, payments, AI, and sensors |
| AI/ML on mobile | ONNX model deployment, on-device LLMs, speech recognition and synthesis |
| Production incidents at 2 AM | Engineers who debug distributed systems, not just read stack traces |
| Architecture that survives growth | Cloud-native, event-driven, Kubernetes, microservices designed for scale |

### The numbers speak for themselves

- **50+ enterprise clients** across Europe — banking, manufacturing, energy, public sector
- **8+ years** building production software without excuses
- **500+ open-source packages** downloaded monthly by developers worldwide
- **Microsoft Partner** since 2022

### Clients who trust us

ABB · Intesa Sanpaolo · Tenaris · Reply · Aubay · Prometeia · Comune di Milano · FIMAP · Altran · BCC

### Your project can't wait until next sprint

If you're reading this README, you're probably already deep into an observability implementation. You might be hitting limits with the existing Dart OTel SDK, struggling with bundle size in your Flutter app, or trying to figure out why your traces disappear under load.

We've solved these exact problems for companies you know. Let's solve them for you.

[Contact PurpleSoft](https://www.purplesoft.io/cerchi-contatti-software-house-a-monza-e-milano/) · [purplesoft.io](https://www.purplesoft.io) · [developers@purplesoft.io](mailto:developers@purplesoft.io) · [+39 0362 148 3978](tel:+3903621483978)## License

AGPL-3.0 — see [LICENSE](LICENSE) for details.




