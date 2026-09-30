package com.edde746.plezy

internal object PlaybackStartupWatchdog {
    const val STALL_TIMEOUT_MS = 30_000L
    const val READY_WITHOUT_FRAME_TIMEOUT_MS = 10_000L

    enum class Reason {
        STALLED,
        READY_WITHOUT_FRAME,
        HARD_LIMIT,
    }

    fun evaluate(
        nowMs: Long,
        attemptStartedAtMs: Long,
        lastProgressAtMs: Long,
        readyWithoutFrameAtMs: Long,
        hardTimeoutMs: Long,
        playerReady: Boolean,
        hasVideoFormat: Boolean,
    ): Reason? {
        if (nowMs - attemptStartedAtMs >= hardTimeoutMs) return Reason.HARD_LIMIT
        if (playerReady && hasVideoFormat && readyWithoutFrameAtMs > 0L &&
            nowMs - readyWithoutFrameAtMs >= READY_WITHOUT_FRAME_TIMEOUT_MS
        ) {
            return Reason.READY_WITHOUT_FRAME
        }
        if ((!playerReady || !hasVideoFormat) &&
            nowMs - lastProgressAtMs >= STALL_TIMEOUT_MS
        ) {
            return Reason.STALLED
        }
        return null
    }
}
