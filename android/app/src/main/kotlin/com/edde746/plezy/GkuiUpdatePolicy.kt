package com.edde746.plezy

internal data class GkuiRelease(
    val version: String,
    val tag: String,
    val assetName: String,
    val assetUrl: String,
    val assetSize: Long,
    val sha256: String,
    val releaseUrl: String,
)

internal object GkuiUpdatePolicy {
    private val versionPattern = Regex("^[0-9]+(?:\\.[0-9]+){2}$")
    private val sha256Pattern = Regex("^[0-9a-f]{64}$")

    fun versionFromTag(tag: String): String? {
        val version = tag.removePrefix("gkui-v")
        return version.takeIf { tag.startsWith("gkui-v") && versionPattern.matches(it) }
    }

    fun expectedAssetName(version: String): String =
        "plezy-gkui-$version-armeabi-v7a.apk"

    fun isNewer(candidate: String, current: String): Boolean {
        val candidateParts = versionParts(candidate) ?: return false
        val currentParts = versionParts(current) ?: return false
        for (index in candidateParts.indices) {
            if (candidateParts[index] != currentParts[index]) {
                return candidateParts[index] > currentParts[index]
            }
        }
        return false
    }

    fun normalizedDigest(value: String): String? {
        val digest = value.removePrefix("sha256:").lowercase()
        return digest.takeIf(sha256Pattern::matches)
    }

    fun isTrustedAssetUrl(url: String, tag: String, assetName: String): Boolean {
        val prefix = "https://github.com/jialim/plezy-gkui/releases/download/$tag/"
        return url == prefix + assetName
    }

    fun isTrustedDownloadHost(scheme: String, host: String): Boolean =
        scheme == "https" && (
            host == "github.com" ||
                host == "objects.githubusercontent.com" ||
                host == "release-assets.githubusercontent.com" ||
                host.endsWith(".githubusercontent.com")
            )

    private fun versionParts(value: String): List<Int>? {
        if (!versionPattern.matches(value)) return null
        return value.split('.').map { part -> part.toIntOrNull() ?: return null }
    }
}
