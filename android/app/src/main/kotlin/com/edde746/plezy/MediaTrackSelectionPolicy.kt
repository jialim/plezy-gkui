package com.edde746.plezy

internal data class MediaTrackCandidate(
    val id: String?,
    val language: String?,
    val label: String?,
    val codec: String?,
)

internal object MediaTrackSelectionPolicy {
    fun bestIndex(
        candidates: List<MediaTrackCandidate>,
        requestedId: String?,
        requestedLanguage: String?,
        requestedTitle: String?,
        requestedCodec: String?,
    ): Int? {
        if (candidates.isEmpty()) return null
        return candidates.indices.maxByOrNull { index ->
            val candidate = candidates[index]
            var score = 0
            if (!requestedId.isNullOrBlank() && candidate.id == requestedId) score += 1_000
            if (languageMatches(candidate.language, requestedLanguage)) score += 300
            score += textScore(candidate.label, requestedTitle, exact = 150, partial = 80)
            score += textScore(candidate.codec, requestedCodec, exact = 30, partial = 15)
            score
        }
    }

    fun subtitleMimeType(codec: String?, path: String?): String? {
        val value = codec?.lowercase()?.trim().orEmpty()
        return when {
            value in setOf("srt", "subrip") || path.orEmpty().lowercase().endsWith(".srt") ->
                "application/x-subrip"
            value in setOf("ass", "ssa") || path.orEmpty().lowercase().let {
                it.endsWith(".ass") || it.endsWith(".ssa")
            } -> "text/x-ssa"
            value in setOf("vtt", "webvtt") || path.orEmpty().lowercase().endsWith(".vtt") ->
                "text/vtt"
            value in setOf("ttml", "dfxp") || path.orEmpty().lowercase().let {
                it.endsWith(".ttml") || it.endsWith(".dfxp")
            } -> "application/ttml+xml"
            value in setOf("mov_text", "tx3g") -> "application/x-quicktime-tx3g"
            else -> null
        }
    }

    private fun languageMatches(left: String?, right: String?): Boolean {
        if (left.isNullOrBlank() || right.isNullOrBlank()) return false
        return normalizeLanguage(left) == normalizeLanguage(right)
    }

    private fun normalizeLanguage(language: String): String {
        val primary = language.lowercase().trim().substringBefore('-').substringBefore('_')
        return when (primary) {
            "eng" -> "en"
            "zho", "chi" -> "zh"
            "jpn" -> "ja"
            "kor" -> "ko"
            "msa", "may" -> "ms"
            "ind" -> "id"
            "tha" -> "th"
            "vie" -> "vi"
            "spa" -> "es"
            "fra", "fre" -> "fr"
            "deu", "ger" -> "de"
            else -> primary
        }
    }

    private fun textScore(
        left: String?,
        right: String?,
        exact: Int,
        partial: Int,
    ): Int {
        if (left.isNullOrBlank() || right.isNullOrBlank()) return 0
        val a = left.lowercase().trim()
        val b = right.lowercase().trim()
        return when {
            a == b -> exact
            a.contains(b) || b.contains(a) -> partial
            else -> 0
        }
    }
}
