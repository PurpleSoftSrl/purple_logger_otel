import 'package:test/test.dart';
import 'package:purple_logger/purple_logger.dart';
import 'package:purple_logger_otel/purple_logger_otel.dart';

/// A concrete [OtelLogger] for testing the abstract base class.
final class _TestOtelLogger implements OtelLogger {
  @override
  final String category;

  final List<_EmittedRecord> emitted = [];

  _TestOtelLogger({required this.category});

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

    final allProps = <String, Object?>{};
    allProps.addAll(LoggingScope.currentProperties);
    if (properties != null) allProps.addAll(properties);
    if (error != null) {
      allProps['error.type'] = error.runtimeType.toString();
      allProps['error.message'] = error.toString();
    }
    if (stackTrace != null) {
      allProps['error.stackTrace'] = stackTrace.toString();
    }
    final traceCtx = extractTraceContext();
    if (traceCtx.isValid) {
      allProps['traceId'] = traceCtx.traceId!;
      allProps['spanId'] = traceCtx.spanId!;
    }
    final filteredProps = <String, Object>{};
    for (final entry in allProps.entries) {
      final v = entry.value;
      if (v != null) filteredProps[entry.key] = v;
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

  @override
  void emitToOtel({
    required int severityNumber,
    required String severityText,
    required String body,
    required Map<String, Object> attributes,
  }) {
    emitted.add(_EmittedRecord(
      severityNumber: severityNumber,
      severityText: severityText,
      body: body,
      attributes: Map.of(attributes),
    ));
  }

  @override
  TraceContext extractTraceContext() => TraceContext.empty;

  @override
  int severityNumber(PurpleLogLevel level) {
    switch (level) {
      case PurpleLogLevel.trace: return 1;
      case PurpleLogLevel.debug: return 5;
      case PurpleLogLevel.info: return 9;
      case PurpleLogLevel.warning: return 13;
      case PurpleLogLevel.error: return 17;
      case PurpleLogLevel.fatal: return 21;
      case PurpleLogLevel.none: return 0;
    }
  }

  @override
  String severityText(PurpleLogLevel level) {
    switch (level) {
      case PurpleLogLevel.trace: return 'TRACE';
      case PurpleLogLevel.debug: return 'DEBUG';
      case PurpleLogLevel.info: return 'INFO';
      case PurpleLogLevel.warning: return 'WARN';
      case PurpleLogLevel.error: return 'ERROR';
      case PurpleLogLevel.fatal: return 'FATAL';
      case PurpleLogLevel.none: return '';
    }
  }

  // Convenience methods — delegate to log()
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
  void error(Object? message, {Object? error, StackTrace? stackTrace, Map<String, Object?>? properties}) =>
      log(PurpleLogLevel.error, message, properties: properties, error: error, stackTrace: stackTrace);

  @override
  void fatal(Object? message, {Object? error, StackTrace? stackTrace, Map<String, Object?>? properties}) =>
      log(PurpleLogLevel.fatal, message, properties: properties, error: error, stackTrace: stackTrace);
}

/// A concrete [OtelLoggerProvider] for testing.
final class _TestOtelProvider extends OtelLoggerProvider {
  @override
  OtelLogger createOtelLogger(String category) =>
      _TestOtelLogger(category: category);
}

final class _EmittedRecord {
  final int severityNumber;
  final String severityText;
  final String body;
  final Map<String, Object> attributes;

  _EmittedRecord({
    required this.severityNumber,
    required this.severityText,
    required this.body,
    required this.attributes,
  });
}

void main() {
  group('level_mapping', () {
    test('severityNumber maps all PurpleLogLevel values correctly', () {
      expect(severityNumber(PurpleLogLevel.trace), equals(1));
      expect(severityNumber(PurpleLogLevel.debug), equals(5));
      expect(severityNumber(PurpleLogLevel.info), equals(9));
      expect(severityNumber(PurpleLogLevel.warning), equals(13));
      expect(severityNumber(PurpleLogLevel.error), equals(17));
      expect(severityNumber(PurpleLogLevel.fatal), equals(21));
      expect(severityNumber(PurpleLogLevel.none), equals(0));
    });

    test('severityNumber matches PurpleLogLevel.severityNumber', () {
      for (final level in PurpleLogLevel.values) {
        expect(
          severityNumber(level),
          equals(level.severityNumber),
          reason: 'severityNumber($level) should match ${level}.severityNumber',
        );
      }
    });

    test('severityText returns OTel standard labels', () {
      expect(severityText(PurpleLogLevel.trace), equals('TRACE'));
      expect(severityText(PurpleLogLevel.debug), equals('DEBUG'));
      expect(severityText(PurpleLogLevel.info), equals('INFO'));
      expect(severityText(PurpleLogLevel.warning), equals('WARN'));
      expect(severityText(PurpleLogLevel.error), equals('ERROR'));
      expect(severityText(PurpleLogLevel.fatal), equals('FATAL'));
      expect(severityText(PurpleLogLevel.none), equals(''));
    });
  });

  group('OtelSeverityMapping', () {
    test('mixin provides same mapping as standalone functions', () {
      final logger = _TestOtelLogger(category: 'Test');
      for (final level in PurpleLogLevel.values) {
        expect(logger.severityNumber(level), equals(severityNumber(level)));
        expect(logger.severityText(level), equals(severityText(level)));
      }
    });
  });

  group('TraceContext', () {
    test('empty context is not valid', () {
      expect(TraceContext.empty.isValid, isFalse);
      expect(TraceContext.empty.traceId, isNull);
      expect(TraceContext.empty.spanId, isNull);
    });

    test('context with values is valid', () {
      final ctx = TraceContext(traceId: 'abc123', spanId: 'def456');
      expect(ctx.isValid, isTrue);
      expect(ctx.traceId, equals('abc123'));
      expect(ctx.spanId, equals('def456'));
    });

    test('context with only traceId is not valid', () {
      final ctx = TraceContext(traceId: 'abc123');
      expect(ctx.isValid, isFalse);
    });
  });

  group('OtelLoggerProvider', () {
    test('createLogger returns OtelLogger with correct category', () {
      final provider = _TestOtelProvider();
      final logger = provider.createLogger('TestCategory');
      expect(logger, isA<OtelLogger>());
      expect(logger.category, equals('TestCategory'));
    });

    test('createLogger caches loggers by category', () {
      final provider = _TestOtelProvider();
      final logger1 = provider.createLogger('Cache');
      final logger2 = provider.createLogger('Cache');
      expect(identical(logger1, logger2), isTrue);
    });

    test('createLogger returns different loggers for different categories', () {
      final provider = _TestOtelProvider();
      final logger1 = provider.createLogger('Cat1');
      final logger2 = provider.createLogger('Cat2');
      expect(identical(logger1, logger2), isFalse);
    });

    test('dispose clears cached loggers', () {
      final provider = _TestOtelProvider();
      provider.createLogger('Temp');
      provider.dispose();
      final logger = provider.createLogger('Temp');
      expect(logger, isA<OtelLogger>());
    });
  });

  group('OtelLogger', () {
    test('isEnabled returns true for all levels except none', () {
      final logger = _TestOtelLogger(category: 'Test');
      for (final level in PurpleLogLevel.values) {
        if (level == PurpleLogLevel.none) {
          expect(logger.isEnabled(level), isFalse);
        } else {
          expect(logger.isEnabled(level), isTrue,
              reason: 'isEnabled should be true for $level');
        }
      }
    });

    test('beginScope returns LoggingScope with given properties', () {
      final logger = _TestOtelLogger(category: 'Test');
      final scope = logger.beginScope({'requestId': 'abc'});
      expect(scope, isA<LoggingScope>());
      expect(scope.effectiveProperties, containsPair('requestId', 'abc'));
    });

    test('log with none level is no-op', () {
      final logger = _TestOtelLogger(category: 'Test');
      logger.log(PurpleLogLevel.none, 'should be ignored');
      expect(logger.emitted, isEmpty);
    });

    test('log emits with correct severity', () {
      final logger = _TestOtelLogger(category: 'Test');
      logger.info('hello OTel');
      expect(logger.emitted.length, equals(1));
      expect(logger.emitted.first.severityNumber, equals(9));
      expect(logger.emitted.first.severityText, equals('INFO'));
      expect(logger.emitted.first.body, equals('hello OTel'));
    });

    test('log attaches error properties', () {
      final logger = _TestOtelLogger(category: 'Test');
      final error = Exception('test error');
      logger.error('something failed', error: error);
      expect(logger.emitted.length, equals(1));
      expect(logger.emitted.first.severityNumber, equals(17));
      expect(logger.emitted.first.attributes, contains('error.type'));
      expect(logger.emitted.first.attributes, contains('error.message'));
    });

    test('log merges scope properties', () {
      final logger = _TestOtelLogger(category: 'Test');
      final scope = logger.beginScope({'requestId': 'abc-123'});
      scope.run(() {
        logger.info('inside scope');
      });
      expect(logger.emitted.length, equals(1));
      expect(logger.emitted.first.body, equals('inside scope'));
      expect(logger.emitted.first.attributes, containsPair('requestId', 'abc-123'));
    });

    test('convenience methods delegate to log', () {
      final logger = _TestOtelLogger(category: 'Test');
      logger.trace('trace msg');
      logger.debug('debug msg');
      logger.info('info msg');
      logger.warning('warn msg');
      logger.error('error msg');
      logger.fatal('fatal msg');
      expect(logger.emitted.length, equals(6));
      expect(logger.emitted[0].severityNumber, equals(1));  // trace
      expect(logger.emitted[1].severityNumber, equals(5));  // debug
      expect(logger.emitted[2].severityNumber, equals(9));  // info
      expect(logger.emitted[3].severityNumber, equals(13)); // warning
      expect(logger.emitted[4].severityNumber, equals(17)); // error
      expect(logger.emitted[5].severityNumber, equals(21)); // fatal
    });

    test('log filters null values from attributes', () {
      final logger = _TestOtelLogger(category: 'Test');
      logger.info('test', properties: {'key1': 'value1', 'key2': null});
      expect(logger.emitted.first.attributes, containsPair('key1', 'value1'));
      expect(logger.emitted.first.attributes, isNot(contains('key2')));
    });
  });
}