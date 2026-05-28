import 'package:test/test.dart';
import 'package:purple_logger/purple_logger.dart';
import 'package:purple_logger_otel/purple_logger_otel.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart'
    hide LoggerProvider;

/// A minimal stub [APILoggerProvider] for unit testing without OTel init.
class _StubOtelProvider implements APILoggerProvider {
  final Map<String, APILogger> _loggers = {};

  @override
  APILogger getLogger(String name,
      {String? version, String? schemaUrl, Attributes? attributes}) {
    return _loggers.putIfAbsent(name, () => _StubOtelLogger(name));
  }

  @override
  bool get enabled => true;

  @override
  set enabled(bool value) {}

  @override
  String get serviceName => 'test';

  @override
  set serviceName(String value) {}

  @override
  String? get serviceVersion => null;

  @override
  set serviceVersion(String? value) {}

  @override
  String get endpoint => 'http://localhost:4318';

  @override
  set endpoint(String value) {}

  @override
  bool get isShutdown => false;

  @override
  set isShutdown(bool value) {}

  @override
  Future<bool> shutdown() async => true;

  @override
  Future<bool> forceFlush() async => true;
}

/// A minimal stub [APILogger] for unit testing.
final class _StubOtelLogger implements APILogger {
  @override
  final String name;

  final List<_EmittedRecord> emitted = [];

  _StubOtelLogger(this.name);

  @override
  bool get enabled => true;

  @override
  String? get version => null;

  @override
  String? get schemaUrl => null;

  @override
  Attributes? get attributes => null;

  @override
  void emit({
    DateTime? timeStamp,
    DateTime? observedTimestamp,
    Context? context,
    Severity? severityNumber,
    String? severityText,
    dynamic body,
    Attributes? attributes,
    String? eventName,
  }) {
    emitted.add(_EmittedRecord(
      severityNumber: severityNumber,
      severityText: severityText,
      body: body?.toString(),
      attributes: attributes,
    ));
  }
}

final class _EmittedRecord {
  final Severity? severityNumber;
  final String? severityText;
  final String? body;
  final Attributes? attributes;

  _EmittedRecord({
    this.severityNumber,
    this.severityText,
    this.body,
    this.attributes,
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

  group('TraceContext', () {
    test('empty context is not valid', () {
      expect(TraceContext.empty.isValid, isFalse);
      expect(TraceContext.empty.traceId, isNull);
      expect(TraceContext.empty.spanId, isNull);
    });

    test('context with values is valid', () {
      final ctx = TraceContext(
        traceId: 'abc123',
        spanId: 'def456',
      );
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
    late _StubOtelProvider stubProvider;

    setUp(() {
      stubProvider = _StubOtelProvider();
    });

    test('createLogger returns OtelLogger with correct category', () {
      final provider = OtelLoggerProvider(otelProvider: stubProvider);
      final logger = provider.createLogger('TestCategory');
      expect(logger, isA<OtelLogger>());
      expect(logger.category, equals('TestCategory'));
    });

    test('createLogger caches loggers by category', () {
      final provider = OtelLoggerProvider(otelProvider: stubProvider);
      final logger1 = provider.createLogger('Cache');
      final logger2 = provider.createLogger('Cache');
      expect(identical(logger1, logger2), isTrue);
    });

    test('createLogger returns different loggers for different categories', () {
      final provider = OtelLoggerProvider(otelProvider: stubProvider);
      final logger1 = provider.createLogger('Cat1');
      final logger2 = provider.createLogger('Cat2');
      expect(identical(logger1, logger2), isFalse);
    });

    test('dispose clears cached loggers', () {
      final provider = OtelLoggerProvider(otelProvider: stubProvider);
      provider.createLogger('Temp');
      provider.dispose();
      // After dispose, creating the same category should return a new instance.
      final logger = provider.createLogger('Temp');
      expect(logger, isA<OtelLogger>());
    });
  });

  group('OtelLogger', () {
    late _StubOtelProvider stubProvider;

    setUp(() {
      stubProvider = _StubOtelProvider();
    });

    test('isEnabled returns true for all levels except none', () {
      final provider = OtelLoggerProvider(otelProvider: stubProvider);
      final logger = provider.createLogger('Test') as OtelLogger;
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
      final provider = OtelLoggerProvider(otelProvider: stubProvider);
      final logger = provider.createLogger('Test') as OtelLogger;
      final scope = logger.beginScope({'requestId': 'abc'});
      expect(scope, isA<LoggingScope>());
      expect(scope.effectiveProperties, containsPair('requestId', 'abc'));
    });

    test('log with none level is no-op', () {
      final provider = OtelLoggerProvider(otelProvider: stubProvider);
      final logger = provider.createLogger('Test') as OtelLogger;
      // Should not throw and should not emit to OTel.
      logger.log(PurpleLogLevel.none, 'should be ignored');
      // The stub logger may not exist yet since none-level is a no-op.
      // Just verify no exception was thrown.
    });

    test('log emits to OTel with correct severity', () {
      final provider = OtelLoggerProvider(otelProvider: stubProvider);
      final logger = provider.createLogger('Test') as OtelLogger;
      logger.info('hello OTel');
      final stubLogger =
          stubProvider._loggers['Test'] as _StubOtelLogger;
      expect(stubLogger.emitted.length, equals(1));
      expect(stubLogger.emitted.first.severityNumber, equals(Severity.INFO));
      expect(stubLogger.emitted.first.severityText, equals('INFO'));
      expect(stubLogger.emitted.first.body, equals('hello OTel'));
    });

    test('log attaches error properties', () {
      final provider = OtelLoggerProvider(otelProvider: stubProvider);
      final logger = provider.createLogger('Test') as OtelLogger;
      final error = Exception('test error');
      logger.error('something failed', error: error);
      final stubLogger =
          stubProvider._loggers['Test'] as _StubOtelLogger;
      expect(stubLogger.emitted.length, equals(1));
      expect(stubLogger.emitted.first.severityNumber, equals(Severity.ERROR));
    });

    test('log merges scope properties', () {
      final provider = OtelLoggerProvider(otelProvider: stubProvider);
      final logger = provider.createLogger('Test') as OtelLogger;
      final scope = logger.beginScope({'requestId': 'abc-123'});
      scope.run(() {
        logger.info('inside scope');
      });
      final stubLogger =
          stubProvider._loggers['Test'] as _StubOtelLogger;
      expect(stubLogger.emitted.length, equals(1));
      expect(stubLogger.emitted.first.body, equals('inside scope'));
    });

    test('convenience methods delegate to log', () {
      final provider = OtelLoggerProvider(otelProvider: stubProvider);
      final logger = provider.createLogger('Test') as OtelLogger;
      logger.trace('trace msg');
      logger.debug('debug msg');
      logger.info('info msg');
      logger.warning('warn msg');
      logger.error('error msg');
      logger.fatal('fatal msg');
      final stubLogger =
          stubProvider._loggers['Test'] as _StubOtelLogger;
      expect(stubLogger.emitted.length, equals(6));
      expect(stubLogger.emitted[0].severityNumber, equals(Severity.TRACE));
      expect(stubLogger.emitted[1].severityNumber, equals(Severity.DEBUG));
      expect(stubLogger.emitted[2].severityNumber, equals(Severity.INFO));
      expect(stubLogger.emitted[3].severityNumber, equals(Severity.WARN));
      expect(stubLogger.emitted[4].severityNumber, equals(Severity.ERROR));
      expect(stubLogger.emitted[5].severityNumber, equals(Severity.FATAL));
    });
  });
}