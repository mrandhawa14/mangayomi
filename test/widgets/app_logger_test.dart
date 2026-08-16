import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/utils/log/logger.dart';
import 'package:path/path.dart' as path;

/// The log file has a ceiling, and it holds while the app is running.
///
/// The ceiling was always intended. It was only ever applied at startup
/// though, which trims the previous run's file and never the one being
/// written, so a session that never ends had no ceiling at all. That is the
/// normal way a television is used.
void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mangayomi_logger_test');
    file = File(path.join(dir.path, 'logs.txt'));
    await AppLogger.openFile(file);
  });

  tearDown(() async {
    await AppLogger.dispose();
    await dir.delete(recursive: true);
  });

  /// Lets the roll, which is deliberately off the caller's thread, finish.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a long session does not grow the file without end', () async {
    // Comfortably past the ceiling: ~4 MB of lines if nothing stopped it.
    for (var i = 0; i < 8000; i++) {
      AppLogger.log('line $i ${'x' * 500}');
      if (i % 100 == 0) await settle();
    }
    await settle();
    await AppLogger.dispose();

    final size = await file.length();
    expect(
      size,
      lessThan(300 * 1024),
      reason: 'wrote roughly 4 MB; the file should have rolled, not grown',
    );
  });

  test('logging still works after a roll', () async {
    for (var i = 0; i < 4000; i++) {
      AppLogger.log('filler $i ${'y' * 500}');
      if (i % 100 == 0) await settle();
    }
    await settle();

    AppLogger.log('after the roll');
    await settle();
    await AppLogger.dispose();

    expect(await file.readAsString(), contains('after the roll'));
  });

  test('a line that repeats is counted, not written again', () async {
    // What a layout error does: the same stack, every frame.
    for (var i = 0; i < 500; i++) {
      AppLogger.log('RenderFlex overflowed by 42 pixels');
    }
    AppLogger.log('something else');
    await settle();
    await AppLogger.dispose();

    final written = await file.readAsString();
    final occurrences = 'RenderFlex overflowed'.allMatches(written).length;
    expect(
      occurrences,
      1,
      reason: '500 identical reports should leave one line behind',
    );
    expect(written, contains('repeated 499 more times'));
  });

  test('an empty file starts from zero, not from the last session', () async {
    AppLogger.log('first session');
    await AppLogger.dispose();

    await AppLogger.openFile(file);
    AppLogger.log('second session');
    await settle();
    await AppLogger.dispose();

    final written = await file.readAsString();
    expect(written, contains('first session'));
    expect(written, contains('second session'));
  });
}
