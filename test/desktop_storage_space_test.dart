import 'dart:io';
import 'dart:typed_data';

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

  test('query failure stops unknown-length writes before output', () async {
    final directory = await Directory.systemTemp.createTemp('bd_capacity_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/partial');
    final sink = file.openWrite();
    sink.done.ignore();
    final guard = StorageSpaceGuard(file.path, -1,
        capacity: (_) => throw const FileSystemException('query failed'));
    await expectLater(guard.write(sink, [1, 2, 3]),
        throwsA(predicate(isDownloadStorageFailure)));
    await sink.close();
    expect(await file.length(), 0);
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
