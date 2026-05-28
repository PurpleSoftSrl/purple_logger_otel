/// OpenTelemetry bridge provider for purple_logger.
///
/// [OtelLoggerProvider] is a [LoggerProvider] that routes [LogEvent]s
/// from purple_logger to OpenTelemetry via [dartastic_opentelemetry].
///
/// Each [LogEvent] is converted to an OTel log record with:
/// - Severity number and text mapped from [PurpleLogLevel]
/// - Structured properties as OTel attributes
/// - Scope properties merged into attributes
/// - Trace context (traceId, spanId) auto-extracted from the current OTel context
/// - Error and stack trace attached as attributes
///
/// ```dart
/// import 'package:purple_logger/purple_logger.dart';
/// import 'package:purple_logger_otel/purple_logger_otel.dart';
///
/// void main() async {
///   await OTel.initialize(
///     serviceName: 'my-service',
///     endpoint: 'http://localhost:4318',
///   );
///
///   final factory = LoggingBuilder()
///     .addProvider(OtelLoggerProvider())
///     .addConsole()
///     .build();
///
///   final logger = factory.createLogger('MyApp');
///   logger.info('Hello OTel!');
///
///   factory.dispose();
/// }
/// ```
library;

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart'
    hide LoggerProvider;
import 'package:purple_logger/purple_logger.dart';

import 'context_extractor.dart';
import 'level_mapping.dart';

/// A [LoggerProvider] that routes [LogEvent]s to OpenTelemetry.
///
/// Use this as a drop-in provider in the [LoggingBuilder] pipeline.
/// It creates one OTel logger per purple_logger category and bridges
/// every [LogEvent] to the OTel logs signal.
final class OtelLoggerProvider extends LoggerProvider {
  final Map<String, OtelLogger> _loggers = {};

  /// The OTel LoggerProvider used to create OTel loggers.
  final APILoggerProvider _otelProvider;

  /// Creates an [OtelLoggerProvider].
  ///
  /// [otelProvider] — an OTel `LoggerProvider` instance (e.g. from
  /// `OTel.loggerProvider()` after calling `OTel.initialize()`).
  OtelLoggerProvider({required APILoggerProvider otelProvider})
      : _otelProvider = otelProvider;

  @override
  Logger createLogger(String category) {
    return _loggers.putIfAbsent(
      category,
      () => OtelLogger(
        category: category,
        otelProvider: _otelProvider,
      ),
    );
  }

  @override
  void dispose() {
    _loggers.clear();
  }
}

/// A [Logger] that bridges [LogEvent]s to an OTel logger.
///
/// Created internally by [OtelLoggerProvider]. You should not need to
/// instantiate this directly.
final class OtelLogger with LoggerConvenience implements Logger {
  @override
  final String category;

  final APILoggerProvider _otelProvider;
  APILogger? _otelLogger;

  OtelLogger({required this.category, required APILoggerProvider otelProvider})
      : _otelProvider = otelProvider;

  APILogger _getOtelLogger() {
    return _otelLogger ??= _otelProvider.getLogger(category);
  }

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

    final otelLogger = _getOtelLogger();

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

    // Build OTel attributes (filter null values).
    final filtered = <String, Object>{};
    for (final entry in allProps.entries) {
      final value = entry.value;
      if (value != null) {
        filtered[entry.key] = value;
      }
    }
    final attrs = OTel.attributesFromMap(filtered);

    // Emit to OTel.
    otelLogger.emit(
      severityNumber: _mapSeverity(level),
      severityText: severityText(level),
      body: message?.toString() ?? '',
      attributes: attrs,
    );
  }

  @override
  LoggingScope beginScope(Map<String, Object?> properties) =>
      LoggingScope(properties);

  /// Maps [PurpleLogLevel] to dartastic's [Severity] enum.
  Severity _mapSeverity(PurpleLogLevel level) {
    switch (level) {
      case PurpleLogLevel.trace:
        return Severity.TRACE;
      case PurpleLogLevel.debug:
        return Severity.DEBUG;
      case PurpleLogLevel.info:
        return Severity.INFO;
      case PurpleLogLevel.warning:
        return Severity.WARN;
      case PurpleLogLevel.error:
        return Severity.ERROR;
      case PurpleLogLevel.fatal:
        return Severity.FATAL;
      case PurpleLogLevel.none:
        return Severity.UNSPECIFIED;
    }
  }
}