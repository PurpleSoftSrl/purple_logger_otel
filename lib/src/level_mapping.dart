/// Maps [PurpleLogLevel] to OpenTelemetry [Severity] numbers.
///
/// Follows the OTel Logs specification severity mapping:
/// https://opentelemetry.io/docs/specs/otel/logs/data-model/#mapping-severitynumber
library;

import 'package:purple_logger/purple_logger.dart';

// dartastic_opentelemetry re-exports Severity from its API package.
// We import it conditionally to avoid hard-coding the internal path.
// The actual import is in otel_logger_provider.dart where the dependency is used.

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