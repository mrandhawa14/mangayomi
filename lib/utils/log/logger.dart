import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/providers/storage_provider.dart';
import 'package:path/path.dart' as path;

class AppLogger {
  /// How large logs.txt may get before it is rolled back to empty.
  ///
  /// This was already the intended ceiling, but it was only ever applied at
  /// startup, which caps the *previous* run's file and never the one being
  /// written. A session that stays up for days, which is the normal way a
  /// television is used, therefore had no ceiling at all.
  static const int _maxBytes = 100 * 1024;

  static File? _logFile;
  static IOSink? _sink;
  static bool _initialized = false;
  static bool _busy = false;

  /// Bytes written to the current file, tracked as they are written so the
  /// size is known without asking the filesystem on every line.
  static int _written = 0;
  static bool _rolling = false;

  /// The last line, and how many times it has repeated since.
  ///
  /// A layout error that survives a frame tends to survive the next one too,
  /// and `FlutterError.onError` reports it every time. Left alone, one broken
  /// frame writes its whole stack sixty times a second.
  static String? _previous;
  static int _repeats = 0;

  /// Initialize the logger
  static Future<void> init() async {
    if (_initialized || _busy) return;
    _busy = true;
    try {
      final enabled = (await isar.settings.get(227))?.enableLogs ?? false;
      if (!enabled) return;
      final storage = StorageProvider();
      final directory = await storage.getDefaultDirectory();
      await openFile(File(path.join(directory!.path, 'logs.txt')));

      log('\n\nLogger initialized\n\n');
    } finally {
      _busy = false;
    }
  }

  /// Points the logger at a file. Split out of [init] so the size ceiling can
  /// be exercised without an Isar instance and a real storage directory behind
  /// it.
  @visibleForTesting
  static Future<void> openFile(File file) async {
    _logFile = file;

    if (await file.exists() && await file.length() > _maxBytes) {
      await file.delete();
    }
    if (!await file.exists()) {
      await file.create(recursive: true);
    }

    _written = await file.length();
    _previous = null;
    _repeats = 0;
    _sink = file.openWrite(mode: FileMode.append);
    _initialized = true;
  }

  static void log(String message, {LogLevel logLevel = LogLevel.info}) {
    if (!_initialized || _sink == null) return;

    // The same line again: count it rather than writing it out a second time.
    if (message == _previous) {
      _repeats++;
      return;
    }
    if (_repeats > 0) {
      final repeated = _repeats;
      _repeats = 0;
      _write('  ... previous line repeated $repeated more times');
      if (_sink == null) return;
    }
    _previous = message;

    final now = DateTime.now();
    final timestamp =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year.toString().padLeft(4, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    _write('[$timestamp][${logLevel.toString()}] $message');
  }

  static void _write(String line) {
    _sink!.writeln(line);
    _written += line.length + 1;
    if (_written <= _maxBytes || _rolling) return;

    // Roll back to empty rather than letting the file grow for the life of the
    // session. A television is left on for days, and a full disk slows down
    // the whole device rather than only this app.
    _rolling = true;
    final sink = _sink;
    // Dropped while the roll is in flight, which costs a handful of lines and
    // is what keeps this method synchronous for its callers.
    _sink = null;
    unawaited(() async {
      try {
        await sink?.flush();
        await sink?.close();
        await _logFile?.writeAsString('');
        _written = 0;
        _previous = null;
        _repeats = 0;
        if (_logFile != null) {
          _sink = _logFile!.openWrite(mode: FileMode.append);
        }
      } finally {
        _rolling = false;
      }
    }());
  }

  static Future<void> dispose() async {
    if (!_initialized || _busy) return;
    _busy = true;
    try {
      await _sink?.flush();
      await _sink?.close();
      _sink = null;
      _logFile = null;
      _initialized = false;
    } finally {
      _busy = false;
    }
  }
}

enum LogLevel {
  debug,
  info,
  warning,
  error;

  @override
  String toString() {
    switch (this) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARNING';
      case LogLevel.error:
        return 'ERROR';
    }
  }
}
