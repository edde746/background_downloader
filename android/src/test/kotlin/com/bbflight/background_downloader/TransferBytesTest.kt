package com.bbflight.background_downloader

import android.app.Notification
import android.content.Context
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class TransferBytesTest {
    private class FakeJobContext(override var task: Task) : TaskJobContext {
        override val appContext: Context
            get() = throw UnsupportedOperationException("not needed for byte transfer")
        override var notificationConfig: NotificationConfig? = null
        override var notificationId: Int = 0
        override var notificationProgress: Double = 2.0
        override var networkSpeed: Double = -1.0
        override var taskCanResume: Boolean = false
        override var notificationConfigJsonString: String? = null
        override val isTaskStopped: Boolean = false
        override val willRunAgain: Boolean = false
        override val platformStopReason: Int = 0
        override suspend fun runAgain() = true
        override suspend fun cancelRunAgain() {}
        override var runInForeground: Boolean = false
        override val isActive: Boolean = true

        override suspend fun setForegroundNotification(
            notificationId: Int,
            notification: Notification,
            notificationType: Int
        ) {
        }

        override fun getInputLong(key: String, defaultValue: Long): Long = defaultValue
        override fun getInputString(key: String): String? = null
        override suspend fun updateNotification(
            task: Task,
            status: TaskStatus,
            progress: Double,
            timeRemaining: Long
        ) {
        }

        override fun updateEstimatedNetworkBytes(downloadBytes: Long, uploadBytes: Long) {}
    }

    /** Records each progress value offered for posting, with the bytes written at that moment */
    private class RecordingRunner(context: TaskJobContext, private val bytesWritten: () -> Int) :
        TaskRunner(context) {
        val offered = mutableListOf<Pair<Double, Int>>()

        override fun shouldSendProgressUpdate(currentProgress: Double, now: Long): Boolean {
            offered.add(currentProgress to bytesWritten())
            return false
        }
    }

    @Test
    fun countsEachTransferredByteOnce() {
        val task = Task(
            url = "https://example.com/video.mkv",
            filename = "video.mkv",
            headers = mapOf(),
            baseDirectory = BaseDirectory.applicationDocuments,
            group = "test",
            updates = Updates.statusAndProgress,
            allowPause = true,
            taskType = "DownloadTask"
        )
        val payload = ByteArray(5 * TaskRunner.bufferSize + 123) { it.toByte() }
        val output = ByteArrayOutputStream()
        val runner = RecordingRunner(FakeJobContext(task)) { output.size() }

        val status = runBlocking {
            runner.transferBytes(
                ByteArrayInputStream(payload), output, payload.size.toLong(), task
            )
        }

        assertEquals(TaskStatus.complete, status)
        assertArrayEquals(payload, output.toByteArray())
        // bytesTotal is the offset stored in resume data on pause and timeout
        assertEquals(payload.size.toLong(), runner.bytesTotal)
        assertTrue(runner.offered.isNotEmpty())
        for ((progress, written) in runner.offered) {
            assertEquals(minOf(written.toDouble() / payload.size, 0.999), progress, 1e-9)
        }
    }
}
