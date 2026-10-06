package com.bbflight.background_downloader

import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RunHandoffTest {
    @Test
    fun theNextRunOfATaskWaitsForTheStoppedRunToFinish() = runTest {
        val stopped = RunHandoff.awaitTurn("waits")
        val next = async { RunHandoff.awaitTurn("waits") }
        runCurrent()
        assertFalse(next.isCompleted)

        RunHandoff.endTurn("waits", stopped)
        runCurrent()
        assertTrue(next.isCompleted)
        RunHandoff.endTurn("waits", next.await())
    }

    @Test
    fun runsOfOtherTasksDoNotWait() = runTest {
        val running = RunHandoff.awaitTurn("busy")
        val other = async { RunHandoff.awaitTurn("idle") }
        runCurrent()
        assertTrue(other.isCompleted)
        RunHandoff.endTurn("idle", other.await())
        RunHandoff.endTurn("busy", running)
    }

    @Test
    fun aRunCanceledWhileWaitingHoldsBackLaterRunsUntilTheStoppedRunFinishes() = runTest {
        val stopped = RunHandoff.awaitTurn("canceled")
        val canceled = async { RunHandoff.awaitTurn("canceled") }
        runCurrent()
        val later = async { RunHandoff.awaitTurn("canceled") }
        runCurrent()

        canceled.cancel()
        runCurrent()
        assertFalse(later.isCompleted)

        RunHandoff.endTurn("canceled", stopped)
        runCurrent()
        assertTrue(later.isCompleted)
        RunHandoff.endTurn("canceled", later.await())
    }
}
