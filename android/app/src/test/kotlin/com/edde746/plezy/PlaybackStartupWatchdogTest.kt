package com.edde746.plezy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlaybackStartupWatchdogTest {
    @Test
    fun networkProgressKeepsSlowZurgStartupAlive() {
        assertNull(
            PlaybackStartupWatchdog.evaluate(
                nowMs = 80_000L,
                attemptStartedAtMs = 0L,
                lastProgressAtMs = 70_000L,
                readyWithoutFrameAtMs = 0L,
                hardTimeoutMs = 120_000L,
                playerReady = false,
                hasVideoFormat = false,
            ),
        )
    }

    @Test
    fun thirtySecondsWithoutBufferOrNetworkProgressStalls() {
        assertEquals(
            PlaybackStartupWatchdog.Reason.STALLED,
            PlaybackStartupWatchdog.evaluate(
                nowMs = 40_000L,
                attemptStartedAtMs = 0L,
                lastProgressAtMs = 10_000L,
                readyWithoutFrameAtMs = 0L,
                hardTimeoutMs = 120_000L,
                playerReady = false,
                hasVideoFormat = false,
            ),
        )
    }

    @Test
    fun readyVideoWithoutFrameFailsQuickly() {
        assertEquals(
            PlaybackStartupWatchdog.Reason.READY_WITHOUT_FRAME,
            PlaybackStartupWatchdog.evaluate(
                nowMs = 25_000L,
                attemptStartedAtMs = 0L,
                lastProgressAtMs = 24_000L,
                readyWithoutFrameAtMs = 15_000L,
                hardTimeoutMs = 120_000L,
                playerReady = true,
                hasVideoFormat = true,
            ),
        )
    }

    @Test
    fun progressCannotExtendPastHardSafetyLimit() {
        assertEquals(
            PlaybackStartupWatchdog.Reason.HARD_LIMIT,
            PlaybackStartupWatchdog.evaluate(
                nowMs = 120_000L,
                attemptStartedAtMs = 0L,
                lastProgressAtMs = 119_999L,
                readyWithoutFrameAtMs = 0L,
                hardTimeoutMs = 120_000L,
                playerReady = false,
                hasVideoFormat = false,
            ),
        )
    }
}
