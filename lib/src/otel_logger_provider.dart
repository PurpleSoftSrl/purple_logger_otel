/// OpenTelemetry bridge abstractions for purple_logger.
///
/// This file defines the **abstract** interfaces that any OTel SDK bridge
/// must implement. Concrete implementations live in companion packages
/// (e.g. `purple_logger_otel_dartastic`).
///
/// The architecture follows the same pattern as Dart's `http` package:
/// - `purple_logger_otel` — interfaces + mapping utilities (zero SDK deps)
/// - `purple_logger_otel_dartastic` — concrete bridge using dartastic_opentelemetry
library;

import 'package:purple_logger/purple_logger.dart';

import 'context_extractor.dart';
import 'level_mapping.dart';

/// Abstract [LoggerProvider] that bridges purple_logger events to an OTel SDK.
///
/// Subclasses must implement [createOtelLogger] to produce an SDK-specific
/// logger instance for a given category.
///
/// Usage:
/// ```dart
/// // With dartastic_opentelemetry:
/// final provider = DartasticOtelLoggerProvider(otelProvider: OTel.loggerProvider());
/// final factory = LoggingBuilder().addProvider(provider).build();
/// ```
abstract class OtelLoggerProvider extends LoggerProvider {
  final Map<String, OtelLogger> _loggers = {};

  @override
  Logger createLogger(String category) {
    return _loggers.putIfAbsent(
      category,
      () => createOtelLogger(category),
    );
  }

  /// Creates an [OtelLogger] for the given [category].
  ///
  /// Subclasses must return a concrete logger that bridges to the
  /// underlying OTel SDK.
  OtelLogger createOtelLogger(String category);

  @override
  void dispose() {
    _loggers.clear();
  }
}

/// Abstract [Logger] that bridges purple_logger events to an OTel SDK.
///
/// Subclasses must implement [emitToOtel] and [extractTraceContext] to
/// send the assembled log record to the underlying OTel SDK.
///
/// This class handles:
/// - Merging scope properties + caller properties
/// - Attaching error info (`error.type`, `error.message`, `error.stackTrace`)
/// - Extracting trace context (traceId, spanId) via [extractTraceContext]
/// - Mapping severity levels via [severityNumber] / [severityText]
abstract class OtelLogger implements Logger, OtelSeverityMapping {
  @override
  final String category;

  OtelLogger({required this.category});

  @override
  bool isEnabled(PurpleLogLevel level) => level != PurpleLogLevel.none;

  @override
  void log(
    PurpleLogLevel level,
    Object? message, {
    Map<String, Object?>? properties,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!isEnabled(level)) return;

    // Merge scope properties + caller properties.
    final allProps = <String, Object?>{};
    allProps.addAll(LoggingScope.currentProperties);
    if (properties != null) allProps.addAll(properties);

    // Attach error info.
    if (error != null) {
      allProps['error.type'] = error.runtimeType.toString();
      allProps['error.message'] = error.toString();
    }
    if (stackTrace != null) {
      allProps['error.stackTrace'] = stackTrace.toString();
    }

    // Extract trace context for log-trace correlation.
    final traceCtx = extractTraceContext();
    if (traceCtx.isValid) {
      allProps['traceId'] = traceCtx.traceId!;
      allProps['spanId'] = traceCtx.spanId!;
    }

    // Filter null values (OTel attributes cannot be null).
    final filteredProps = <String, Object>{};
    for (final entry in allProps.entries) {
      final v = entry.value;
      if (v != null) {
        filteredProps[entry.key] = v;
      }
    }

    emitToOtel(
      severityNumber: severityNumber(level),
      severityText: severityText(level),
      body: message?.toString() ?? '',
      attributes: filteredProps,
    );
  }

  @override
  LoggingScope beginScope(Map<String, Object?> properties) =>
      LoggingScope(properties);

  /// Emits a log record to the underlying OTel SDK.
  ///
  /// [severityNumber] — OTel severity number (1–24, or 0 for UNSPECIFIED).
  /// [severityText] — Short uppercase label (e.g. 'INFO', 'ERROR').
  /// [body] — The log message.
  /// [attributes] — Pre-filtered key-value pairs (no null values).
  void emitToOtel({
    required int severityNumber,
    required String severityText,
    required String body,
    required Map<String, Object> attributes,
  });

  /// Extracts trace context (traceId, spanId) from the current OTel context.
  ///
  /// Returns [TraceContext.empty] if no span is active or OTel is not initialized.
  TraceContext extractTraceContext();
}
