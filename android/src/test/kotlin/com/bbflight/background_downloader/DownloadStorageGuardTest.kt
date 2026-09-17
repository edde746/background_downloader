package com.bbflight.background_downloader

import java.io.File
import java.io.FileOutputStream
import org.junit.Assert.*
import org.junit.Test

class DownloadStorageGuardTest {
    @Test
    fun unknownLengthCapacityDropRemovesPartialBeforeReturningFailure() {
        val partial = File.createTempFile("download-guard", ".part")
        val completed = File.createTempFile("download-complete", ".bin")
        completed.writeText("existing completed download")
        val floor = 256L * 1024 * 1024
        var available = floor + 128 * 1024
        var closed = false
        val output = object : FileOutputStream(partial) {
            override fun close() {
                closed = true
                super.close()
            }
        }
        try {
            val guarded = DownloadStorageGuard(
                output, -1, -1,
                { DownloadVolumeCapacity(available, 1024L * 1024 * 1024) },
                { assertTrue("Close descriptor before deletion", closed); partial.delete() }
            )
            guarded.use {
                it.write(ByteArray(64 * 1024))
                assertEquals(64L * 1024, partial.length())
                available = floor + 1024 // another writer consumes the volume
                try {
                    it.write(ByteArray(64 * 1024))
                    fail("Expected runtime capacity failure for unknown length")
                } catch (e: DownloadStorageException) {
                    assertTrue(e.message!!.startsWith("Insufficient space to store"))
                    assertFalse("Incomplete output must already be removed", partial.exists())
                    assertTrue("Descriptor must already be closed", closed)
                    assertEquals("existing completed download", completed.readText())
                }
            }
        } finally {
            output.close()
            partial.delete()
            completed.delete()
        }
    }
}
