/// Trace context abstraction for OpenTelemetry log-trace correlation.
///
/// [TraceContext] is a vendor-neutral value object that carries traceId
/// and spanId. Concrete bridge packages (e.g. `purple_logger_otel_dartastic`)
/// provide the [extractTraceContext] implementation that reads from the
/// actual OTel SDK context.
library;

import 'package:purple_logger/purple_logger.dart';

/// Trace context extracted from the current OTel context.
///
/// When a span is active (e.g. inside an OTel tracing scope), this carries
/// the `traceId` and `spanId` so they can be attached to log records.
/// This enables correlation between logs and traces in backends like
/// Jaeger, Tempo, or Azure Monitor.
final class TraceContext {
  /// The trace identifier, or `null` if no span is active.
  final String? traceId;

  /// The span identifier, or `null` if no span is active.
  final String? spanId;

  /// Whether a valid trace context was found.
  bool get isValid => traceId != null && spanId != null;

  const TraceContext({this.traceId, this.spanId});

  /// An empty context with no trace information.
  static const empty = TraceContext();
}

/// Mixin that provides the standard OTel severity mapping for [PurpleLogLevel].
///
/// Apply this mixin to any [OtelLogger] subclass to get the canonical
/// `severityNumber()` and `severityText()` methods for free.
mixin OtelSeverityMapping {
  /// Maps a [PurpleLogLevel] to its OTel severity number.
  ///
  /// | PurpleLogLevel | OTel SeverityNumber |
  /// |----------------|--------------------:|
  /// | trace          | 1 (TRACE)           |
  /// | debug          | 5 (DEBUG)           |
  /// | info           | 9 (INFO)            |
  /// | warning        | 13 (WARN)           |
  /// | error          | 17 (ERROR)          |
  /// | fatal          | 21 (FATAL)          |
  /// | none           | 0 (UNSPECIFIED)     |
  int severityNumber(PurpleLogLevel level) {
    switch (level) {
      case PurpleLogLevel.trace:
        return 1;
      case PurpleLogLevel.debug:
        return 5;
      case PurpleLogLevel.info:
        return 9;
      case PurpleLogLevel.warning:
        return 13;
      case PurpleLogLevel.error:
        return 17;
      case PurpleLogLevel.fatal:
        return 21;
      case PurpleLogLevel.none:
        return 0;
    }
  }

  /// Returns the OTel severity text for a [PurpleLogLevel].
  ///
  /// OTel recommends short uppercase labels matching the severity band.
  String severityText(PurpleLogLevel level) {
    switch (level) {
      case PurpleLogLevel.trace:
        return 'TRACE';
      case PurpleLogLevel.debug:
        return 'DEBUG';
      case PurpleLogLevel.info:
        return 'INFO';
      case PurpleLogLevel.warning:
        return 'WARN';
      case PurpleLogLevel.error:
        return 'ERROR';
      case PurpleLogLevel.fatal:
        return 'FATAL';
      case PurpleLogLevel.none:
        return '';
    }
  }
}