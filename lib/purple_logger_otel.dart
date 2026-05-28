/// OpenTelemetry bridge for purple_logger.
///
/// Routes structured [LogEvent]s from [purple_logger] to OpenTelemetry
/// via [dartastic_opentelemetry], supporting OTLP gRPC/HTTP export.
///
/// ```dart
/// import 'package:purple_logger/purple_logger.dart';
/// import 'package:purple_logger_otel/purple_logger_otel.dart';
///
/// final factory = LoggingBuilder()
///   .addProvider(OtelLoggerProvider(
///     endpoint: 'http://localhost:4318',
///     serviceName: 'my-service',
///   ))
///   .addConsole()
///   .build();
/// ```
library;

export 'src/otel_logger_provider.dart';
export 'src/level_mapping.dart';
export 'src/context_extractor.dart';