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

    private fun hide(
        visible: Boolean = true,
        playWhenReady: Boolean = true,
        renderedFirstFrame: Boolean = true,
        seeking: Boolean = false,
        dialogOpen: Boolean = false,
        idleMs: Long = ControlsAutoHide.IDLE_MS,
    ) = ControlsAutoHide.shouldHide(visible, playWhenReady, renderedFirstFrame, seeking, dialogOpen, idleMs)

    @Test fun controlsHideAfterIdlePlaybackWithoutAnyTap() {
        assertTrue(hide())
        assertFalse(hide(idleMs = ControlsAutoHide.IDLE_MS - 1))
    }

    @Test fun controlsStayWhilePausedSeekingOrChoosingTracks() {
        assertFalse(hide(playWhenReady = false))
        assertFalse(hide(seeking = true))
        assertFalse(hide(dialogOpen = true))
        assertFalse(hide(renderedFirstFrame = false))
        assertFalse(hide(visible = false))
    }

    @Test fun bufferingPlaybackStillHidesControls() {
        // Rebuffering keeps playWhenReady; the status label reports it instead.
        assertTrue(hide(playWhenReady = true, idleMs = 60_000L))
    }

    @Test fun controlsKeepTheirDesignSizeOnThe480dpHeadUnit() {
        assertEquals(1f, PlayerControlsLayout.scale(480f), 0.001f)
    }

    @Test fun controlsShrinkOnADenserScreenWithoutBecomingTiny() {
        // 800x480 pixels at hdpi is 320dp tall.
        assertEquals(320f / 480f, PlayerControlsLayout.scale(320f), 0.001f)
        assertEquals(0.65f, PlayerControlsLayout.scale(200f), 0.001f)
        assertEquals(1.4f, PlayerControlsLayout.scale(1080f), 0.001f)
    }
}
