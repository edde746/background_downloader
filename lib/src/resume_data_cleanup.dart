import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'chunk.dart';
import 'models.dart';
import 'task.dart';

final _windowsAbsolutePathRegExp = RegExp(r'^[a-zA-Z]:[\\/]');

/// Deletes temporary files referenced by [resumeData].
///
/// Android and desktop resumable downloads store the temporary file path in
/// [ResumeData.data]. iOS resume data is opaque, and Android URI downloads may
/// store a destination URI instead of a private temp file, so URI values are
/// intentionally left alone here.
Future<void> deleteResumeDataTempFiles(
  ResumeData resumeData, {
  required Future<ResumeData?> Function(String taskId) getResumeData,
  Logger? log,
}) async {
  if (Platform.isIOS) return;

  if (resumeData.task is ParallelDownloadTask) {
    await _deleteParallelResumeTempFiles(
      resumeData,
      getResumeData: getResumeData,
      log: log,
    );
    return;
  }

  await deleteResumeDataTempFile(resumeData.data, log: log);
}

Future<void> _deleteParallelResumeTempFiles(
  ResumeData resumeData, {
  required Future<ResumeData?> Function(String taskId) getResumeData,
  Logger? log,
}) async {
  try {
    final chunks = List<Chunk>.from(
      jsonDecode(resumeData.data, reviver: Chunk.listReviver),
    );
    for (final chunk in chunks) {
      final chunkResumeData = await getResumeData(chunk.task.taskId);
      if (chunkResumeData != null) {
        await deleteResumeDataTempFiles(
          chunkResumeData,
          getResumeData: getResumeData,
          log: log,
        );
      }
    }
  } catch (e) {
    log?.fine('Could not parse parallel resume data for cleanup: $e');
  }
}

Future<Set<String>> resumeDataTaskIds(
  ResumeData resumeData, {
  required Future<ResumeData?> Function(String taskId) getResumeData,
  Logger? log,
}) async {
  final taskIds = {resumeData.taskId};
  if (resumeData.task is! ParallelDownloadTask) return taskIds;

  try {
    final chunks = List<Chunk>.from(
      jsonDecode(resumeData.data, reviver: Chunk.listReviver),
    );
    for (final chunk in chunks) {
      taskIds.add(chunk.task.taskId);
      final chunkResumeData = await getResumeData(chunk.task.taskId);
      if (chunkResumeData != null) {
        taskIds.addAll(
          await resumeDataTaskIds(
            chunkResumeData,
            getResumeData: getResumeData,
            log: log,
          ),
        );
      }
    }
  } catch (e) {
    log?.fine('Could not parse parallel resume data for cleanup: $e');
  }
  return taskIds;
}

Future<bool> deleteResumeDataTempFile(String value, {Logger? log}) async {
  final filePath = _filePathFromResumeData(value);
  if (filePath == null) return false;

  final file = File(filePath);
  try {
    if (await file.exists()) {
      await file.delete();
      log?.fine('Deleted resume temp file $filePath');
      return true;
    }
  } on FileSystemException catch (e) {
    log?.fine('Could not delete resume temp file $filePath: $e');
  }
  return false;
}

String? _filePathFromResumeData(String value) {
  if (value.isEmpty) return null;
  if (Platform.isWindows && _windowsAbsolutePathRegExp.hasMatch(value)) {
    return value;
  }
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) return null;
  return value;
}
