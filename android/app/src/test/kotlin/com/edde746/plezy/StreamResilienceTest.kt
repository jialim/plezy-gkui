package com.edde746.plezy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StreamResilienceTest {
    @Test
    fun bufferFollowsHeapWithinBounds() {
        val mib = 1024L * 1024L
        assertEquals((64 * mib / 3).toInt(), StreamResilience.targetBufferBytes(64 * mib))
        assertEquals((12 * mib).toInt(), StreamResilience.targetBufferBytes(24 * mib))
        assertEquals((32 * mib).toInt(), StreamResilience.targetBufferBytes(512 * mib))
    }

    @Test
    fun readRetriesBackOffAndCoverLongZurgPauses() {
        assertEquals(1_000L, StreamResilience.retryDelayMs(null, 1))
        assertEquals(3_000L, StreamResilience.retryDelayMs(503, 3))
        assertEquals(5_000L, StreamResilience.retryDelayMs(null, 9))
        val total = (1..StreamResilience.LOAD_RETRY_COUNT).sumOf { StreamResilience.retryDelayMs(null, it)!! }
        assertTrue("retries should span at least 30 seconds", total >= 30_000L)
    }

    @Test
    fun clientErrorsFailFastExceptTimeoutAndRateLimit() {
        assertNull(StreamResilience.retryDelayMs(404, 1))
        assertNull(StreamResilience.retryDelayMs(401, 1))
        assertEquals(1_000L, StreamResilience.retryDelayMs(408, 1))
        assertEquals(1_000L, StreamResilience.retryDelayMs(429, 1))
    }

    @Test
    fun serverAndNetworkFailuresReconnect() {
        assertTrue(StreamResilience.isReconnectable("network", null))
        assertTrue(StreamResilience.isReconnectable("http", 502))
        assertTrue(StreamResilience.isReconnectable("http", 503))
        assertFalse(StreamResilience.isReconnectable("http", 404))
        assertFalse(StreamResilience.isReconnectable("decoder", null))
        assertFalse(StreamResilience.isReconnectable("source", null))
    }

    @Test
    fun reconnectDelaysGrow() {
        assertEquals(2_000L, StreamResilience.reconnectDelayMs(1))
        assertEquals(4_000L, StreamResilience.reconnectDelayMs(2))
        assertEquals(8_000L, StreamResilience.reconnectDelayMs(3))
    }

    @Test
    fun earlyEndIsOnlyFarFromTheKnownDuration() {
        val duration = 45L * 60_000L
        assertTrue(StreamResilience.endedEarly(20L * 60_000L, duration))
        assertFalse(StreamResilience.endedEarly(duration - 30_000L, duration))
        assertFalse(StreamResilience.endedEarly(30_000L, 0L))
        assertFalse(StreamResilience.endedEarly(30_000L, 90_000L))
    }
}
