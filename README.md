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

---

---

---


---

## Built by PurpleSoft

**[PurpleSoft S.r.l.](https://www.purplesoft.io)** — software house with offices in Monza, Milano, and Lugano (Switzerland). Since 2017.

> We build what doesn't exist yet.

### The sectors we dominate

**Conversational AI & Voice Assistants.** We design and ship end-to-end AI voice platforms — from the physical device (ESP32 with custom Opus codec firmware) to the cloud backend (.NET 10, ASP.NET Core, Blazor Server) to the mobile companion app (Flutter with BLE). Our multi-agent LLM architecture orchestrates 8 specialized agents (conversation, memory, content enrichment, exploration, and more) with a multi-layered memory system spanning graph, episodic, and working memory — including adaptive forgetting, poison detection via z-score outlier analysis, and automatic episodic-to-semantic compression. We deploy DeepSeek V4 for primary inference at 53x lower cost than GPT-4o, with multi-provider fallback across OpenAI, Anthropic, Gemini, and Ollama. Our scientific research pipeline uses a 4-scorer verification chain (NLI dual-label, cross-model consistency, evidence retrieval, hallucination detection) with consensus voting to ensure factual accuracy. We design RAG pipelines with HNSW vector search (1024-dim embeddings), hybrid full-text + semantic RRF, sharded K-means search, and training-free chunk pre-filtering.

**Fintech & Payments.** We build payment orchestration layers that abstract Stripe, SumUp, Nexi, Axerve, PayPal, Google Pay, and Apple Pay behind a single API — plus Bitcoin, Ethereum, and 100+ cryptocurrencies. Our engineers have shipped POS terminal firmware, fiscal receipt systems compliant with Italian *Fattura Elettronica* regulations, and cash register management platforms processing millions of transactions.

**Cybersecurity & Identity.** We ship post-quantum cryptography implementations using NIST-standardized algorithms on .NET 10 (ML-KEM, ML-DSA, SLH-DSA) — the cryptography standard that will replace RSA and ECC. Our authentication infrastructure integrates SPID (Italian public digital identity), OAuth 2.0/OpenID Connect across Google, Apple, Microsoft, Facebook, Instagram, LinkedIn, and GitHub. We build digital signature platforms with PKCS#11 hardware security module support, handling the full envelope lifecycle from document preparation to legally binding execution.

**Artificial Intelligence & On-Device ML.** We deploy ONNX models to phones via custom Dart runtime bindings with GPU acceleration. We integrate Litert and MediaPipe for on-device LLM inference. We build neural text-to-speech engines that run across all 6 Flutter platforms — from Android to Web — and speech recognition systems with Italian dialect support. We design content intelligence pipelines that ingest, enrich via LLM, embed (1024-dim vectors), and serve via hybrid semantic search — at scale: 28,000 items enriched, 30,000 embeddings generated, 14 pipelines with 3 stages each (scrape → enrich → embed). DeepSeek V4 Pro processes content enrichment at a fraction of the cost of GPT-4o.

**Enterprise SaaS & Cloud-Native Architecture.** We architect, build, and operate platforms at enterprise scale. Our .NET 10 monorepo spans 239 C# projects with consistent Azure Pipelines CI/CD, 297 test suites passing, zero build errors. We design multi-engine database abstraction layers (PostgreSQL + pgvector, MySQL, Microsoft SQL Server) with automated schema-to-code generation that produces complete ASP.NET API controllers. Our notification engine handles 6 channels (email, push, SMS, chat, webhook, in-app) with DNS-based email validation and template management. Our audio SDK provides unified TTS/STT across ElevenLabs, DashScope, DeepGram, Whisper, and Windows Speech with Opus/OGG codec support and real-time streaming.

**IoT & Embedded Systems.** We write ESP32 firmware targeting ESP-IDF v5.4 with 21 FreeRTOS tasks, I²S audio pipelines, Opus codec integration, and a 6-state WiFi state machine with validated recovery paths. We build certificate authority infrastructure that generates and manages device TLS certificates with challenge-response verification. We write native Flutter plugins for hardware that doesn't have one yet — from payment terminals to BLE device provisioning to audio codecs.

**Observability & DevOps.** Full-stack observability is the foundation we build our client solutions on. We ship a complete OpenTelemetry SDK for Dart/Flutter (traces, logs, metrics, W3C propagation, OTLP export), enterprise structured logging with file rotation, and auto-instrumentation for HTTP, Dio, and Flutter navigation — all red-team audited with 256 automated tests.

### The technologies we master

Our engineering team works across the full stack — from ESP32 firmware in C to cloud-native backends in C# (.NET 10) to cross-platform mobile apps in Dart/Flutter. We write production code in **C# (.NET 10)**, **Dart**, **TypeScript**, **JavaScript**, **C**, **C++**, **Python**, and **Rust**. Our frameworks of choice are **ASP.NET Core**, **Blazor Server**, **Flutter**, **Angular**, and **React**. Our AI stack spans **DeepSeek**, **OpenAI**, **Anthropic Claude**, **Google Gemini**, **Ollama**, **Microsoft Semantic Kernel**, and **Microsoft Agents.AI**. We operate **Microsoft Azure** (Key Vault, Blob Storage, Resource Manager, IoT Hub, Virtual Machines), deploy on **NGINX**, and manage **PostgreSQL + pgvector**, **MySQL**, **Microsoft SQL Server**, and **ESP-IDF v5.4** at scale. We use **EF Core** with **Npgsql** for data access, **FFmpeg** for audio processing, **LVGL** for embedded displays, and **BLE** for device provisioning. Our CI/CD runs on **Azure Pipelines**.

### Microsoft Partner since 2018 · SumUp Partner · Dell Partner

---

### Trusted by

`ABB` `Intesa Sanpaolo` `Tenaris` `Reply` `Aubay` `Comune di Milano` `BCC` `FIMAP` `Alten` `Altran` `Prometeia` `illimity` `Be Shaping the Future` `DS Group` `NVALUE` `Inoptim` `Docflow` `P&C`

*and 40+ other enterprises across banking, manufacturing, energy, and public sector.*

---

> Your project can't wait. We've solved these exact problems for companies you know.
> Let's solve them for you.

[🌐 **purplesoft.io**](https://www.purplesoft.io) &nbsp;·&nbsp; [📧 **developers@purplesoft.io**](mailto:developers@purplesoft.io) &nbsp;·&nbsp; [📞 **+39 0362 148 3978**](tel:+3903621483978) &nbsp;·&nbsp; [💼 **LinkedIn**](https://www.linkedin.com/company/purplesoft-srl) &nbsp;·&nbsp; [🐙 **GitHub**](https://github.com/purplesoftsrl)

## License

AGPL-3.0 — see [LICENSE](LICENSE) for details.











