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
    fun containerOrderBreaksTiesBetweenUnlabeledSameLanguageTracks() {
        val candidates = listOf(
            MediaTrackCandidate("1", "en", null, "audio/ac3", ordinal = 0),
            MediaTrackCandidate("2", "en", null, "audio/ac3", ordinal = 1),
        )

        assertEquals(1, MediaTrackSelectionPolicy.bestIndex(
            candidates,
            "9002",
            "en",
            null,
            null,
            requestedOrdinal = 1,
        ))
    }

    @Test
    fun exactTitleStillBeatsContainerOrder() {
        val candidates = listOf(
            MediaTrackCandidate(null, "en", "Commentary", null, ordinal = 0),
            MediaTrackCandidate(null, "en", "English", null, ordinal = 1),
        )

        assertEquals(0, MediaTrackSelectionPolicy.bestIndex(
            candidates,
            null,
            "en",
            "Commentary",
            null,
            requestedOrdinal = 1,
        ))
    }

    @Test
    fun mapsExoTrackBackToPlexStreamId() {
        val plexIds = listOf("9001", "9002")

        assertEquals("9002", MediaTrackSelectionPolicy.plexTrackId(
            MediaTrackCandidate("2", "en", null, null, ordinal = 1),
            plexIds,
            embeddedTrackCount = 2,
        ))
        assertEquals("9001", MediaTrackSelectionPolicy.plexTrackId(
            MediaTrackCandidate("9001", "en", null, null, ordinal = null),
            plexIds,
            embeddedTrackCount = 5,
        ))
        assertEquals(null, MediaTrackSelectionPolicy.plexTrackId(
            MediaTrackCandidate("2", "en", null, null, ordinal = 1),
            plexIds,
            embeddedTrackCount = 3,
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
