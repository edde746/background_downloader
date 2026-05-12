import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:background_downloader/src/database.dart';
import 'package:background_downloader/src/persistent_storage.dart';
import 'package:background_downloader/src/models.dart';
import 'package:background_downloader/src/task.dart';

final defaultTask = DownloadTask(
  taskId: 'task1',
  url: 'https://google.com',
  group: 'group',
);

late Database db;
late MockPersistentStorage storage;

void main() {
  setUp(() {
    storage = MockPersistentStorage();
    db = Database(storage);
  });

  tearDown(() {
    db.destroy(); // destroys the singleton
  });

  group('Database Listener Test', () {
    test('emits updated record when listener is active', () async {
      final task = defaultTask;
      final record = TaskRecord(task, TaskStatus.running, 0.0, 100);
      final listener = db.updates;
      final completer = Completer<TaskRecord>();
      listener.listen(completer.complete);
      db.updateRecord(record);
      final emittedRecord = await completer.future;
      expect(emittedRecord, equals(record));
    });

    test('emits multiple updated records when listener is active', () async {
      final task1 = defaultTask;
      final task2 = defaultTask.copyWith(taskId: 'task2');
      final record1 = TaskRecord(task1, TaskStatus.running, 0.0, 100);
      final record2 = TaskRecord(task2, TaskStatus.running, 0.0, 100);
      final listener = db.updates;
      var counter = 0;
      listener.listen((record) => counter++);
      await db.updateRecord(record1);
      await db.updateRecord(record2);
      await Future.delayed(const Duration(seconds: 1));
      expect(counter, equals(2));
    });

    test('two listeners receive the same TaskRecord', () async {
      final task = defaultTask;
      final record = TaskRecord(task, TaskStatus.running, 0.0, 100);
      final listener1 = db.updates;
      final listener2 = db.updates;
      final completer1 = Completer<TaskRecord>();
      final completer2 = Completer<TaskRecord>();
      listener1.listen(completer1.complete);
      listener2.listen(completer2.complete);
      await db.updateRecord(record);
      final emittedRecord1 = await completer1.future;
      final emittedRecord2 = await completer2.future;
      expect(emittedRecord1, equals(record));
      expect(emittedRecord2, equals(record));
    });

    test('deleteRecordWithId discards resume temp file and state', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'bd_resume_cleanup_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final tempFile = File(
        '${tempDir.path}${Platform.pathSeparator}com.bbflight.background_downloader123',
      );
      await tempFile.writeAsString('partial');
      final task = defaultTask.copyWith(taskId: 'cleanup-task');

      await storage.storeTaskRecord(
        TaskRecord(task, TaskStatus.failed, progressFailed, 100),
      );
      await storage.storePausedTask(task);
      await storage.storeResumeData(ResumeData(task, tempFile.path, 50, 'tag'));

      expect(await tempFile.exists(), isTrue);

      await db.deleteRecordWithId(task.taskId);

      expect(await tempFile.exists(), isFalse);
      expect(await storage.retrieveTaskRecord(task.taskId), isNull);
      expect(await storage.retrievePausedTask(task.taskId), isNull);
      expect(await storage.retrieveResumeData(task.taskId), isNull);
    });

    test('deleteRecordWithId preserves file uri resume data targets', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'bd_resume_uri_cleanup_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final targetFile = File(
        '${tempDir.path}${Platform.pathSeparator}destination-file',
      );
      await targetFile.writeAsString('partial');
      final task = defaultTask.copyWith(taskId: 'cleanup-uri-task');

      await storage.storeTaskRecord(
        TaskRecord(task, TaskStatus.failed, progressFailed, 100),
      );
      await storage
          .storeResumeData(ResumeData(task, targetFile.uri.toString()));

      await db.deleteRecordWithId(task.taskId);

      expect(await targetFile.exists(), isTrue);
      expect(await storage.retrieveResumeData(task.taskId), isNull);
    });
  });
}

class MockPersistentStorage implements PersistentStorage {
  final _taskRecords = <String, TaskRecord>{};
  final _pausedTasks = <String, Task>{};
  final _resumeData = <String, ResumeData>{};

  @override
  Future<void> storeTaskRecord(TaskRecord record) async {
    _taskRecords[record.taskId] = record;
  }

  @override
  Future<TaskRecord?> retrieveTaskRecord(String taskId) {
    return Future.value(_taskRecords[taskId]);
  }

  @override
  Future<List<TaskRecord>> retrieveAllTaskRecords() {
    return Future.value(_taskRecords.values.toList());
  }

  @override
  Future<void> removeTaskRecord(String? taskId) async {
    if (taskId == null) {
      _taskRecords.clear();
    } else {
      _taskRecords.remove(taskId);
    }
  }

  @override
  (String, int) get currentDatabaseVersion => ('mock', 1);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> removePausedTask(String? taskId) async {
    if (taskId == null) {
      _pausedTasks.clear();
    } else {
      _pausedTasks.remove(taskId);
    }
  }

  @override
  Future<void> removeResumeData(String? taskId) async {
    if (taskId == null) {
      _resumeData.clear();
    } else {
      _resumeData.remove(taskId);
    }
  }

  @override
  Future<List<Task>> retrieveAllPausedTasks() {
    return Future.value(_pausedTasks.values.toList());
  }

  @override
  Future<List<ResumeData>> retrieveAllResumeData() {
    return Future.value(_resumeData.values.toList());
  }

  @override
  Future<Task?> retrievePausedTask(String taskId) {
    return Future.value(_pausedTasks[taskId]);
  }

  @override
  Future<ResumeData?> retrieveResumeData(String taskId) {
    return Future.value(_resumeData[taskId]);
  }

  @override
  Future<void> storePausedTask(Task task) async {
    _pausedTasks[task.taskId] = task;
  }

  @override
  Future<void> storeResumeData(ResumeData resumeData) async {
    _resumeData[resumeData.taskId] = resumeData;
  }

  @override
  Future<(String, int)> get storedDatabaseVersion =>
      Future.value(currentDatabaseVersion);
}
