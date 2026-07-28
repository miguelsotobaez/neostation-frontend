import 'dart:io';
import 'package:logger/logger.dart';
import 'package:neostation/services/config_service.dart';
import 'package:neostation/utils/log_redaction.dart';

/// Supported log severity levels.
enum LogLevel { info, warning, error, debug }

/// Service responsible for application-wide logging with support for console
/// and file-based output.
///
/// Handles log rotation to prevent excessive disk usage and ensures that logs
/// are persisted across sessions for debugging purposes.
class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  static LoggerService get instance => _instance;

  Logger _logger;
  bool _initialized = false;

  LoggerService._internal()
    : _logger = Logger(
        printer: RedactingPrinter(SimplePrinter(colors: true)),
        filter: ProductionFilter(),
        output: MultiOutput([ConsoleOutput()]),
      );

  /// Initializes the logger, sets up file output, and performs log rotation.
  ///
  /// Rotates the log file if it exceeds 5MB, keeping one historical copy (`.old`).
  Future<void> init() async {
    if (_initialized) return;

    try {
      final logFilePath = await ConfigService.getLogFilePath();
      final logFile = File(logFilePath);

      final logDir = logFile.parent;
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      if (await logFile.exists()) {
        final size = await logFile.length();
        if (size > 5 * 1024 * 1024) {
          final oldLogFile = File('$logFilePath.old');
          if (await oldLogFile.exists()) {
            await oldLogFile.delete();
          }
          await logFile.rename(oldLogFile.path);
        }
      }

      _logger = Logger(
        level: Level.info,
        printer: RedactingPrinter(SimplePrinter(colors: true)),
        filter: CustomProductionFilter(),
        output: MultiOutput([
          ConsoleOutput(),
          FileOutput(file: File(logFilePath)),
        ]),
      );

      _initialized = true;
      i('Logger initialized with file output: $logFilePath');
    } catch (e) {
      // ignore: avoid_print
      print('Error initializing file logger: $e');
    }
  }

  /// Logs a message at the specified [LogLevel].
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    switch (level) {
      case LogLevel.info:
        _logger.i(message, error: error, stackTrace: stackTrace);
        break;
      case LogLevel.warning:
        _logger.w(message, error: error, stackTrace: stackTrace);
        break;
      case LogLevel.error:
        _logger.e(message, error: error, stackTrace: stackTrace);
        break;
      case LogLevel.debug:
        _logger.d(message, error: error, stackTrace: stackTrace);
        break;
    }
  }

  /// Logs a debug-level message.
  void d(String message) => log(message, level: LogLevel.debug);

  /// Logs an info-level message.
  void i(String message) => log(message, level: LogLevel.info);

  /// Logs a warning-level message.
  void w(String message) => log(message, level: LogLevel.warning);

  /// Logs an error-level message with optional error object and stack trace.
  void e(String message, {Object? error, StackTrace? stackTrace}) =>
      log(message, level: LogLevel.error, error: error, stackTrace: stackTrace);
}

/// Strips credentials from every formatted log line before it reaches an
/// output.
///
/// This wraps the printer rather than the log call sites on purpose: the worst
/// leaks come from error objects we never format ourselves — an HTTP client
/// exception carries the full request URI, query string included — so
/// redaction has to happen after the event is rendered and before it is
/// written to the console or the log file.
class RedactingPrinter extends LogPrinter {
  RedactingPrinter(this._inner);

  final LogPrinter _inner;

  @override
  List<String> log(LogEvent event) =>
      _inner.log(event).map(redactSecrets).toList();
}

/// Custom log filter that permits INFO level logs even in production/release environments.
class CustomProductionFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return event.level.index >= level!.index;
  }
}
