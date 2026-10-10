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

internal data class ReleaseSummary(
    val index: Int,
    val tag: String,
    val draft: Boolean,
    val prerelease: Boolean,
)

internal object GkuiUpdatePolicy {
    private val versionPattern = Regex("^[0-9]+(?:\\.[0-9]+){2}$")
    private val sha256Pattern = Regex("^[0-9a-f]{64}$")
    private val assetUrlPattern =
        Regex("^https://github\\.com/[A-Za-z0-9-]+/plezy-gkui/releases/download/([^/]+)/([^/]+)$")

    fun versionFromTag(tag: String): String? {
        val version = tag.removePrefix("gkui-v")
        return version.takeIf { tag.startsWith("gkui-v") && versionPattern.matches(it) }
    }

    fun expectedAssetName(version: String): String =
        "plezy-gkui-$version-armeabi-v7a.apk"

    /** The version in a finished download's file name, or null for anything else. */
    fun versionFromAssetName(name: String): String? {
        val version = name.removePrefix("plezy-gkui-").removeSuffix("-armeabi-v7a.apk")
        return version.takeIf { expectedAssetName(it) == name && versionPattern.matches(it) }
    }

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

    /**
     * The owner segment is not pinned: GitHub redirects a renamed account, and
     * an install must keep updating after it. The installed signing
     * certificate, checked before the installer opens, is the real trust anchor.
     */
    fun isTrustedAssetUrl(url: String, tag: String, assetName: String): Boolean {
        val match = assetUrlPattern.matchEntire(url) ?: return false
        return match.groupValues[1] == tag && match.groupValues[2] == assetName
    }

    /** API redirects (a renamed owner or repository) stay on api.github.com. */
    fun isTrustedApiRedirect(scheme: String, host: String): Boolean =
        scheme == "https" && host == "api.github.com"

    /**
     * Picks the newest stable GKUI release from the repository's release list.
     * The XGIMI build publishes to the same repository, so GitHub's single
     * "latest" release is not necessarily a GKUI one.
     */
    fun newestStableIndex(releases: List<ReleaseSummary>): Int? = releases
        .filter { !it.draft && !it.prerelease && versionFromTag(it.tag) != null }
        .reduceOrNull { best, next ->
            if (isNewer(versionFromTag(next.tag)!!, versionFromTag(best.tag)!!)) next else best
        }
        ?.index

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
