import 'dart:async';

bool useLogger = false;

class Logger {
  static final StreamController<(LoggerLevel, String, DateTime)>
  _logStreamController =
      StreamController<(LoggerLevel, String, DateTime)>.broadcast();

  static StreamController<(LoggerLevel, String, DateTime)>
  get logStreamController => _logStreamController;

  static final List<(LoggerLevel, String, DateTime)> _logs = [];

  static List<(LoggerLevel, String, DateTime)> get logs => _logs;

  static void add(LoggerLevel level, String content) {
    // Capture the time once: calling DateTime.now() twice gave the streamed
    // copy and the stored copy of the same entry different timestamps.
    final entry = (level, content, DateTime.now());
    _logStreamController.add(entry);
    _logs.add(entry);
  }

  static void clear() {
    _logs.clear();
  }
}

enum LoggerLevel { error, warning, info }
