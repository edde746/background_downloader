import 'dart:io';
import 'dart:typed_data';

import 'package:background_downloader/src/desktop/isolate.dart';
import 'package:background_downloader/src/desktop/storage_space.dart';
import 'package:background_downloader/src/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

const _mib = 1024 * 1024;

void main() {
  test('adaptive floor chooses minimum or actual volume percentage', () {
    for (final total in [10 * 1024 * _mib, 100 * 1024 * _mib]) {
      final floor = total ~/ 100 > 256 * _mib ? total ~/ 100 : 256 * _mib;
      var available = floor + 7;
      final guard = StorageSpaceGuard('/target', -1,
          capacity: (_) => (available: available, total: total));
      guard.check(7);
      available--;
      expect(() => guard.check(7), throwsA(predicate(isDownloadStorageFailure)));
    }
  });

  test('disabled never queries storage, fixed MiB preserves its boundary', () {
    StorageSpaceGuard('/target', 0, capacity: (_) => throw StateError('query'))
        .check(1 << 50);
    final guard = StorageSpaceGuard('/target', 2,
        capacity: (_) => (available: 3 * _mib, total: 100 * 1024 * _mib));
    guard.check(_mib);
    expect(() => guard.check(_mib + 1),
        throwsA(predicate(isDownloadStorageFailure)));
  });

  test('unknown capacity does not block writes', () async {
    final directory = await Directory.systemTemp.createTemp('bd_capacity_');
    addTearDown(() => directory.delete(recursive: true));
    for (final capacity in <({int available, int total}) Function(String)>[
      (_) => throw const FileSystemException('query failed'),
      (_) => (available: 0, total: 0),
      (_) => (available: -1, total: 100 * 1024 * _mib),
    ]) {
      final file = File('${directory.path}/partial');
      final sink = file.openWrite();
      sink.done.ignore();
      final guard = StorageSpaceGuard(file.path, -1, capacity: capacity);
      guard.check(1 << 50);
      await guard.write(sink, [1, 2, 3]);
      await sink.close();
      expect(await file.length(), 3);
    }
  });

  test('native query reports the containing volume', () {
    final capacity = desktopVolumeCapacity(
      '${Directory.systemTemp.path}/bd_missing/child',
    );
    expect(capacity.total, greaterThan(0));
    expect(capacity.available, inInclusiveRange(0, capacity.total));
  });

  group('important-usage capacity', () {
    const total = 100 * 1024 * _mib;
    const floor = 1024 * _mib;
    const request = 100 * _mib;

    test('plain refusal defers to purgeable-inclusive capacity', () {
      final guard = StorageSpaceGuard('/target', -1,
          capacity: (_) => (available: floor + 10 * _mib, total: total),
          importantCapacity: (_) => 5 * floor);
      guard.check(request);
    });

    test('plain capacity that fits never queries important usage', () {
      var queries = 0;
      final guard = StorageSpaceGuard('/target', -1,
          capacity: (_) => (available: floor + request, total: total),
          importantCapacity: (_) {
            queries++;
            return 5 * floor;
          });
      guard.check(request);
      guard.check(request);
      expect(queries, 0);
    });

    test('refusal by both reports the figures', () {
      final guard = StorageSpaceGuard('/target', -1,
          capacity: (_) => (available: floor + 10 * _mib, total: total),
          importantCapacity: (_) => floor + 20 * _mib);
      expect(
          () => guard.check(request),
          throwsA(isA<TaskFileSystemException>()
              .having(isDownloadStorageFailure, 'storage failure', isTrue)
              .having(
                  (e) => e.description,
                  'description',
                  allOf(
                    startsWith('Insufficient space to store download: '),
                    contains('needs $request bytes'),
                    contains('reserve of $floor bytes'),
                    contains('${floor + 10 * _mib} bytes free'),
                    contains('${floor + 20 * _mib} for important usage'),
                  ))));
    });

    test('unavailable important usage leaves the plain refusal', () {
      for (final important in <int? Function(String)>[
        (_) => null,
        (_) => 0,
        (_) => throw const FileSystemException('query failed'),
      ]) {
        final guard = StorageSpaceGuard('/target', -1,
            capacity: (_) => (available: floor + 10 * _mib, total: total),
            importantCapacity: important);
        expect(
            () => guard.check(request),
            throwsA(predicate((TaskException e) =>
                isDownloadStorageFailure(e) &&
                e.description.contains('unknown for important usage'))));
      }
    });

    test('a sample serves its age, charged with bytes written since', () {
      var now = DateTime(2026);
      var available = floor + 10 * _mib;
      var important = floor + 2 * request;
      var queries = 0;
      final guard = StorageSpaceGuard('/target', -1,
          capacity: (_) => (available: available, total: total),
          importantCapacity: (_) {
            queries++;
            return important;
          },
          clock: () => now);
      guard.check(request);
      expect(queries, 1);
      // Written since the sample: the estimate still fits.
      available -= 50 * _mib;
      guard.check(request);
      expect(queries, 1);
      // The estimate would refuse; a fresh sample decides, and the system
      // has since purged more.
      available -= 60 * _mib;
      important = floor + 3 * request;
      guard.check(request);
      expect(queries, 2);
      // A refused estimate re-samples, and a refusing fresh sample is final.
      available -= 250 * _mib;
      important = floor + request - 1;
      expect(() => guard.check(request),
          throwsA(predicate(isDownloadStorageFailure)));
      expect(queries, 3);
      // Space purged after the refusal counts at the next check.
      important = 5 * floor;
      guard.check(request);
      expect(queries, 4);
      // An expired sample is replaced even though its estimate fits.
      now = now.add(StorageSpaceGuard.importantSampleAge);
      guard.check(request);
      expect(queries, 5);
    });

    test('macOS reports it for the containing volume', () {
      final path = '${Directory.systemTemp.path}/bd_missing/child';
      final available = desktopVolumeCapacity(path).available;
      final important = desktopImportantCapacity(path);
      if (!Platform.isMacOS) {
        expect(important, isNull);
        return;
      }
      expect(important, greaterThan(0));
      // Purgeable space comes on top; allow for other writers between queries.
      expect(important, greaterThan(available - 1024 * _mib));
    });
  });

  test('out-of-space write errors are storage failures in any language', () {
    final outOfSpace = Platform.isWindows ? [39, 112] : [28];
    for (final code in outOfSpace) {
      setTaskError(FileSystemException(
          'writeFrom failed', '/partial', OSError('Kein Speicherplatz', code)));
      expect(isDownloadStorageFailure(taskException), isTrue);
    }
    setTaskError(const FileSystemException(
        'writeFrom failed', '/partial', OSError('Permission denied', 13)));
    expect(isDownloadStorageFailure(taskException), isFalse);
  });

  test('one large unknown-length event is bounded and rechecks live space',
      () async {
    final directory = await Directory.systemTemp.createTemp('bd_capacity_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/partial');
    final sink = file.openWrite();
    sink.done.ignore();
    var samples = 0;
    final guard = StorageSpaceGuard(file.path, -1, capacity: (_) {
      samples++;
      return (
        available: 256 * _mib + (samples == 1 ? _mib : 0),
        total: 10 * 1024 * _mib,
      );
    });
    await expectLater(guard.write(sink, Uint8List(3 * _mib)),
        throwsA(predicate(isDownloadStorageFailure)));
    await sink.close();
    expect(await file.length(), StorageSpaceGuard.writeSize);
  });

  test('small events sample capacity once per window and stop at its end',
      () async {
    final directory = await Directory.systemTemp.createTemp('bd_capacity_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/partial');
    final sink = file.openWrite();
    sink.done.ignore();
    var samples = 0;
    final guard = StorageSpaceGuard(file.path, -1, capacity: (_) {
      samples++;
      return (
        available: 256 * _mib + (samples <= 2 ? _mib : 0),
        total: 10 * 1024 * _mib,
      );
    });
    // Network-sized events that straddle the window boundary.
    final event = Uint8List(5000);
    Future<void> transfer() async {
      for (var written = 0; written < 3 * _mib; written += event.length) {
        await guard.write(sink, event);
      }
    }

    await expectLater(
        transfer(), throwsA(predicate(isDownloadStorageFailure)));
    await sink.close();
    expect(samples, 3);
    expect(await file.length(), 2 * StorageSpaceGuard.writeSize);
  });

  test('copy refusal retains source and unrelated completed destination',
      () async {
    final directory = await Directory.systemTemp.createTemp('bd_capacity_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source');
    final destination = File('${directory.path}/complete');
    final staging = File('${directory.path}/complete.part');
    await source.writeAsString('download');
    await destination.writeAsString('completed');
    // Native query exercises the actual containing volume. This fixed floor
    // is intentionally larger than any supported physical desktop volume.
    await expectLater(copyWithSpaceGuard(source, staging, 1 << 40),
        throwsA(predicate(isDownloadStorageFailure)));
    expect(await source.readAsString(), 'download');
    expect(await destination.readAsString(), 'completed');
    expect(await staging.exists(), isFalse);
  });
}
