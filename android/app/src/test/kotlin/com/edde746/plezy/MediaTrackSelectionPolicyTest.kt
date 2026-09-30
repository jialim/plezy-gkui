package com.edde746.plezy

import org.junit.Assert.assertEquals
import org.junit.Test

class MediaTrackSelectionPolicyTest {
    @Test
    fun exactPlexTrackIdWins() {
        val candidates = listOf(
            MediaTrackCandidate("41", "en", "English", "srt"),
            MediaTrackCandidate("42", "en", "English forced", "srt"),
        )

        assertEquals(1, MediaTrackSelectionPolicy.bestIndex(candidates, "42", "en", null, null))
    }

    @Test
    fun matchesTwoAndThreeLetterLanguageCodesForAudioOrSubtitles() {
        val candidates = listOf(
            MediaTrackCandidate(null, "jpn", "Japanese", "aac"),
            MediaTrackCandidate(null, "eng", "English", "aac"),
        )

        assertEquals(0, MediaTrackSelectionPolicy.bestIndex(candidates, null, "ja", null, null))
    }

    @Test
    fun titleDistinguishesTracksWithTheSameLanguage() {
        val candidates = listOf(
            MediaTrackCandidate(null, "en", "English", "srt"),
            MediaTrackCandidate(null, "en", "English forced", "srt"),
        )

        assertEquals(1, MediaTrackSelectionPolicy.bestIndex(
            candidates,
            null,
            "en",
            "English forced",
            "srt",
        ))
    }

    @Test
    fun mapsCommonExternalSubtitleFormats() {
        assertEquals("application/x-subrip", MediaTrackSelectionPolicy.subtitleMimeType("srt", null))
        assertEquals("text/x-ssa", MediaTrackSelectionPolicy.subtitleMimeType("ass", null))
        assertEquals("text/vtt", MediaTrackSelectionPolicy.subtitleMimeType(null, "/stream/file.vtt"))
        assertEquals(null, MediaTrackSelectionPolicy.subtitleMimeType("pgs", null))
    }
}
