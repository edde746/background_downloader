import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a storage refusal never schedules a native retry', () {
    final task = DownloadTask(
      url: 'https://example.com/file',
      filename: 'file',
      retries: 5,
    );
    task.decreaseRetriesRemaining();
    final update = TaskStatusUpdate(
      task,
      TaskStatus.failed,
      TaskFileSystemException('Insufficient space to store the file to be downloaded'),
    );

    // The update must be delivered as a final failure (no waitingToRetry
    // emission, no retry timer): processStatusUpdate throws the task back to
    // the native queue otherwise, and the retry storm fills storage again.
    expect(isDownloadStorageFailure(update.exception), isTrue);
  });

  test('ordinary filesystem failures remain retryable', () {
    final task = DownloadTask(
      url: 'https://example.com/file',
      filename: 'file',
      retries: 5,
    );
    final update = TaskStatusUpdate(
      task,
      TaskStatus.failed,
      TaskFileSystemException('file not found'),
    );

    expect(isDownloadStorageFailure(update.exception), isFalse);
  });

  test('storage classification survives JSON round trips', () {
    final exception = TaskFileSystemException(
      'Download storage capacity could not be determined',
    );
    final json = jsonDecode(exception.toJsonString()) as Map<String, dynamic>;
    final decoded = TaskException.fromJson(json);

    expect(isDownloadStorageFailure(exception), isTrue);
    expect(isDownloadStorageFailure(decoded), isTrue);
  });
}
