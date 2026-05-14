import 'dart:io';

import 'package:background_downloader/src/models.dart';
import 'package:background_downloader/src/resume_data_cleanup.dart';
import 'package:background_downloader/src/task.dart';
import 'package:flutter_test/flutter_test.dart';

final _defaultTask = DownloadTask(
  taskId: 'task1',
  url: 'https://example.com/file',
);

void main() {
  group('resume data cleanup', () {
    test('deletes unreferenced legacy temp files from scan directories',
        () async {
      final firstDir = await Directory.systemTemp.createTemp(
        'bd_legacy_cleanup_1_',
      );
      final secondDir = await Directory.systemTemp.createTemp(
        'bd_legacy_cleanup_2_',
      );
      addTearDown(() async {
        for (final directory in [firstDir, secondDir]) {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        }
      });

      final orphan = File(
        '${firstDir.path}${Platform.pathSeparator}com.bbflight.background_downloader123',
      );
      final secondOrphan = File(
        '${secondDir.path}${Platform.pathSeparator}com.bbflight.background_downloader456',
      );
      final referenced = File(
        '${firstDir.path}${Platform.pathSeparator}com.bbflight.background_downloader789',
      );
      final unrelated = File(
        '${firstDir.path}${Platform.pathSeparator}not_background_downloader',
      );
      await Future.wait([
        orphan.writeAsString('orphan'),
        secondOrphan.writeAsString('orphan'),
        referenced.writeAsString('referenced'),
        unrelated.writeAsString('unrelated'),
      ]);

      final deleted = await deleteOrphanedLegacyTempFiles(
        [ResumeData(_defaultTask, referenced.path, 1, 'tag')],
        directories: [firstDir, secondDir, firstDir],
      );

      expect(deleted, 2);
      expect(await orphan.exists(), isFalse);
      expect(await secondOrphan.exists(), isFalse);
      expect(await referenced.exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
    });
  });
}
