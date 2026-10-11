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
