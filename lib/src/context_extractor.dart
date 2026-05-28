/// Extracts trace context from the current OTel [Context].
///
/// When a span is active (e.g. inside an OTel tracing scope), this extractor
/// reads the `traceId` and `spanId` so they can be attached to log records.
///
/// This enables correlation between logs and traces in backends like
/// Jaeger, Tempo, or Azure Monitor.
library;

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

/// Trace context extracted from the current OTel [Context].
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

/// Extracts trace context from the current OTel [Context].
///
/// Returns [TraceContext.empty] if no span is active, the span context
/// is invalid, or OTel has not been initialized.
TraceContext extractTraceContext() {
  try {
    final ctx = Context.current;
    final spanCtx = ctx.spanContext;
    if (spanCtx != null && spanCtx.isValid) {
      return TraceContext(
        traceId: spanCtx.traceId.toString(),
        spanId: spanCtx.spanId.toString(),
      );
    }
  } catch (_) {
    // OTel not initialized — return empty context.
  }
  return TraceContext.empty;
}