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

    test('deletes unreferenced tracked desktop partial files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'bd_part_cleanup_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final orphanDest = File(
        '${tempDir.path}${Platform.pathSeparator}orphan.bin',
      );
      final referencedDest = File(
        '${tempDir.path}${Platform.pathSeparator}referenced.bin',
      );
      final activeDest = File(
        '${tempDir.path}${Platform.pathSeparator}active.bin',
      );
      final replacementDest = File(
        '${tempDir.path}${Platform.pathSeparator}replacement.bin',
      );
      final untrackedPart = File(
        '${tempDir.path}${Platform.pathSeparator}untracked.bin.part',
      );
      final orphanPart = File(partialDownloadFilePath(orphanDest.path));
      final referencedPart = File(partialDownloadFilePath(referencedDest.path));
      final activePart = File(partialDownloadFilePath(activeDest.path));
      final replacementPart =
          File(partialDownloadFilePath(replacementDest.path));
      await Future.wait([
        orphanPart.writeAsString('orphan'),
        referencedPart.writeAsString('referenced'),
        activePart.writeAsString('active'),
        replacementPart.writeAsString('replacement'),
        untrackedPart.writeAsString('untracked'),
      ]);

      final orphanTask = _taskForFile('orphan-task', orphanDest);
      final referencedTask = _taskForFile('referenced-task', referencedDest);
      final activeTask = _taskForFile('active-task', activeDest);
      final replacedTask = _taskForFile('replaced-task', replacementDest);
      final replacementActiveTask = _taskForFile(
        'replacement-active-task',
        replacementDest,
      );

      final deleted = await deleteOrphanedPartialDownloadFiles(
        trackedTasks: [orphanTask, referencedTask, activeTask, replacedTask],
        allResumeData: [
          ResumeData(referencedTask, referencedPart.path, 1, 'tag'),
        ],
        activeTasks: [activeTask, replacementActiveTask],
      );

      final expectedDeleted = Platform.isAndroid ||
              Platform.isWindows ||
              Platform.isMacOS ||
              Platform.isLinux
          ? 1
          : 0;
      expect(deleted, expectedDeleted);
      expect(
        await orphanPart.exists(),
        expectedDeleted == 0 ? isTrue : isFalse,
      );
      expect(await referencedPart.exists(), isTrue);
      expect(await activePart.exists(), isTrue);
      expect(await replacementPart.exists(), isTrue);
      expect(await untrackedPart.exists(), isTrue);
    });
  });
}

DownloadTask _taskForFile(String taskId, File file) {
  return DownloadTask(
    taskId: taskId,
    url: 'https://example.com/${file.uri.pathSegments.last}',
    filename: file.uri.pathSegments.last,
    directory: file.parent.path,
    baseDirectory: BaseDirectory.root,
  );
}
