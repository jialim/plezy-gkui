package com.edde746.plezy

import com.google.android.exoplayer2.C
import com.google.android.exoplayer2.upstream.DefaultLoadErrorHandlingPolicy
import com.google.android.exoplayer2.upstream.HttpDataSource
import com.google.android.exoplayer2.upstream.LoadErrorHandlingPolicy

/**
 * Zurg serves Real-Debrid files to Plex through a remote mount, so reads can
 * pause for several seconds or drop mid-file. These rules keep playback going
 * through those gaps instead of surfacing them as skips or failures.
 */
internal object StreamResilience {
    /** Loader retries before a read error reaches the player (about 40 seconds of backoff). */
    const val LOAD_RETRY_COUNT = 10
    const val MAX_RETRY_DELAY_MS = 5_000L

    /** Player-level reconnects per dropout, after the loader retries are spent. */
    const val RECONNECT_ATTEMPTS = 3

    /** A stream that "ends" this far before the known duration was cut off, not finished. */
    const val EARLY_END_MARGIN_MS = 60_000L

    const val MIN_BUFFER_MS = 15_000
    const val MAX_BUFFER_MS = 50_000
    const val BUFFER_FOR_PLAYBACK_MS = 2_500
    const val BUFFER_AFTER_REBUFFER_MS = 6_000
    private const val MIN_TARGET_BYTES = 12 * 1024 * 1024
    private const val MAX_TARGET_BYTES = 32 * 1024 * 1024

    /**
     * Buffer as much as a third of the app heap allows. The XE1115H reports a
     * 64 MiB heap, giving about 21 MiB instead of the earlier fixed 12 MiB.
     */
    fun targetBufferBytes(maxHeapBytes: Long): Int =
        (maxHeapBytes / 3).coerceIn(MIN_TARGET_BYTES.toLong(), MAX_TARGET_BYTES.toLong()).toInt()

    /** Backoff for the next loader retry, or null when retrying cannot help. */
    fun retryDelayMs(httpStatus: Int?, errorCount: Int): Long? {
        if (httpStatus != null && httpStatus in 400..499 && httpStatus != 408 && httpStatus != 429) {
            return null
        }
        return (errorCount.coerceAtLeast(1) * 1_000L).coerceAtMost(MAX_RETRY_DELAY_MS)
    }

    /** Whether a player error is worth reopening the same stream for. */
    fun isReconnectable(failureKind: String?, httpStatus: Int?): Boolean = when (failureKind) {
        "network" -> true
        "http" -> httpStatus == null || httpStatus >= 500 || httpStatus == 408 || httpStatus == 429
        else -> false
    }

    fun reconnectDelayMs(attempt: Int): Long = 2_000L shl (attempt - 1).coerceIn(0, 4)

    fun endedEarly(positionMs: Long, durationMs: Long): Boolean =
        durationMs > EARLY_END_MARGIN_MS * 2 && positionMs >= 0L &&
            positionMs < durationMs - EARLY_END_MARGIN_MS
}

internal class ZurgLoadErrorHandlingPolicy :
    DefaultLoadErrorHandlingPolicy(StreamResilience.LOAD_RETRY_COUNT) {
    override fun getRetryDelayMsFor(loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
        // Keep the default's non-retryable cases (parser errors, missing files, range errors).
        if (super.getRetryDelayMsFor(loadErrorInfo) == C.TIME_UNSET) return C.TIME_UNSET
        val status = PlaybackDiagnostics.causes(loadErrorInfo.exception)
            .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
            .firstOrNull()?.responseCode
        return StreamResilience.retryDelayMs(status, loadErrorInfo.errorCount) ?: C.TIME_UNSET
    }
}
