/// OpenTelemetry abstractions for purple_logger.
///
/// This package provides vendor-neutral interfaces and utilities for bridging
/// [LogEvent]s from purple_logger to OpenTelemetry. It has **zero dependencies**
/// on any specific OTel SDK — use a concrete implementation package such as
/// `purple_logger_otel_dartastic` for the actual bridge.
///
/// What's here:
/// - [OtelLoggerProvider] — abstract provider that bridges to an OTel SDK
/// - [OtelLogger] — abstract logger that bridges to an OTel SDK
/// - [OtelSeverityMapping] — mixin with standard PurpleLogLevel → OTel mapping
/// - [TraceContext] — value object for traceId/spanId correlation
/// - [severityNumber] / [severityText] — standalone mapping functions
///
/// ```dart
/// import 'package:purple_logger/purple_logger.dart';
/// import 'package:purple_logger_otel/purple_logger_otel.dart';
/// // Plus a concrete implementation:
/// import 'package:purple_logger_otel_dartastic/purple_logger_otel_dartastic.dart';
/// ```
library;

export 'src/otel_logger_provider.dart';
export 'src/level_mapping.dart';
export 'src/context_extractor.dart'; // TraceContext + OtelSeverityMapping
