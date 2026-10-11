package com.edde746.plezy

import org.junit.Assert.*
import org.junit.Test

class PlaybackSessionStateTest {
    @Test fun bufferingPlayIntentResumesAfterWake() {
        val state = PlaybackLifecycle()
        // Buffering has isPlaying=false, but playWhenReady=true.
        state.pause(playWhenReady = true)
        assertTrue(state.paused)
        assertTrue(state.resume())
        assertFalse(state.paused)
        assertFalse(state.resume())
    }

    @Test fun manualPauseRemainsPausedAfterWake() {
        val state = PlaybackLifecycle()
        state.pause(playWhenReady = false)
        assertFalse(state.resume())
    }

    @Test fun repeatedBackgroundNotificationDoesNotLoseIntent() {
        val state = PlaybackLifecycle()
        state.pause(playWhenReady = true)
        state.pause(playWhenReady = false)
        assertTrue(state.resume())
    }

    @Test fun markersArrivingBeforeActivityCreationAreDeliveredOnce() {
        val mailbox = PlaybackMarkerMailbox()
        val markers = listOf(PlaybackMarker("intro", 0, 30000))
        mailbox.begin("first")
        assertTrue(mailbox.post("first", markers))
        assertEquals(markers, mailbox.take("first"))
        assertNull(mailbox.take("first"))
    }

    @Test fun lateMarkersCannotSeekTheNextEpisode() {
        val mailbox = PlaybackMarkerMailbox()
        mailbox.begin("first")
        mailbox.begin("second")
        assertFalse(mailbox.post("first", listOf(PlaybackMarker("intro", 0, 30000))))
        assertNull(mailbox.take("second"))
        mailbox.end("first")
        assertTrue(mailbox.post("second", listOf(PlaybackMarker("intro", 0, 10000))))
        mailbox.end("second")
        assertFalse(mailbox.post("second", emptyList()))
    }

    @Test fun invalidMarkerRangesAreDiscarded() {
        val mailbox = PlaybackMarkerMailbox()
        mailbox.begin("video")
        mailbox.post("video", listOf(PlaybackMarker("intro", -1, 100),
            PlaybackMarker("credits", 200, 100), PlaybackMarker("intro", 0, 100)))
        assertEquals(listOf(PlaybackMarker("intro", 0, 100)), mailbox.take("video"))
    }
}
