package com.edde746.plezy

/** Play intent remains true while buffering or temporarily losing audio focus. */
internal class PlaybackLifecycle {
    var paused = false
        private set
    private var resumeRequested = false

    fun pause(playWhenReady: Boolean) {
        if (!paused) resumeRequested = playWhenReady
        paused = true
    }

    fun resume(): Boolean {
        paused = false
        val requested = resumeRequested
        resumeRequested = false
        return requested
    }
}

internal data class PlaybackMarker(val type: String, val startMs: Long, val endMs: Long)

/** One active session; late responses for earlier videos are never retained. */
internal class PlaybackMarkerMailbox {
    private var sessionId: String? = null
    private var pending: List<PlaybackMarker>? = null

    fun begin(id: String) {
        sessionId = id
        pending = null
    }

    fun post(id: String, markers: List<PlaybackMarker>): Boolean {
        if (id.isBlank() || id != sessionId) return false
        pending = markers.filter { it.startMs >= 0L && it.endMs > it.startMs }
        return true
    }

    fun take(id: String): List<PlaybackMarker>? {
        if (id != sessionId) return null
        val result = pending
        pending = null
        return result
    }

    fun end(id: String) {
        if (sessionId == id) {
            sessionId = null
            pending = null
        }
    }
}

/** When the player's touch controls get out of the way of the video. */
internal object ControlsAutoHide {
    const val IDLE_MS = 5_000L

    fun shouldHide(
        visible: Boolean,
        playWhenReady: Boolean,
        renderedFirstFrame: Boolean,
        seeking: Boolean,
        dialogOpen: Boolean,
        idleMs: Long,
    ): Boolean = visible && playWhenReady && renderedFirstFrame && !seeking && !dialogOpen &&
        idleMs >= IDLE_MS
}

/** Sizing for the in-car player controls. */
internal object PlayerControlsLayout {
    /** The controls are laid out for 480dp of screen height. */
    const val DESIGN_HEIGHT_DP = 480f

    fun scale(screenHeightDp: Float): Float =
        (screenHeightDp / DESIGN_HEIGHT_DP).coerceIn(0.65f, 1.4f)
}
