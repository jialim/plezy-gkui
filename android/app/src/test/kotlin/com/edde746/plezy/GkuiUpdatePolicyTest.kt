package com.edde746.plezy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GkuiUpdatePolicyTest {
    @Test
    fun parsesOnlyGkuiSemanticVersionTags() {
        assertEquals("1.2.9", GkuiUpdatePolicy.versionFromTag("gkui-v1.2.9"))
        assertNull(GkuiUpdatePolicy.versionFromTag("xgimi-lite-v2.22.0-test5"))
        assertNull(GkuiUpdatePolicy.versionFromTag("gkui-v1.2.9-beta"))
    }

    @Test
    fun comparesNumericVersions() {
        assertTrue(GkuiUpdatePolicy.isNewer("1.2.10", "1.2.9"))
        assertFalse(GkuiUpdatePolicy.isNewer("1.2.9", "1.2.9"))
        assertFalse(GkuiUpdatePolicy.isNewer("1.2.8", "1.2.9"))
    }

    @Test
    fun acceptsOnlyExpectedReleaseAsset() {
        val name = GkuiUpdatePolicy.expectedAssetName("1.2.9")
        assertTrue(GkuiUpdatePolicy.isTrustedAssetUrl(
            "https://github.com/jialim/plezy-gkui/releases/download/gkui-v1.2.9/$name",
            "gkui-v1.2.9",
            name,
        ))
        assertFalse(GkuiUpdatePolicy.isTrustedAssetUrl(
            "https://example.com/$name",
            "gkui-v1.2.9",
            name,
        ))
    }

    @Test
    fun validatesDigestAndRedirectHosts() {
        val hash = "a".repeat(64)
        assertEquals(hash, GkuiUpdatePolicy.normalizedDigest("sha256:$hash"))
        assertNull(GkuiUpdatePolicy.normalizedDigest("sha256:not-a-hash"))
        assertTrue(GkuiUpdatePolicy.isTrustedDownloadHost("https", "release-assets.githubusercontent.com"))
        assertFalse(GkuiUpdatePolicy.isTrustedDownloadHost("http", "github.com"))
        assertFalse(GkuiUpdatePolicy.isTrustedDownloadHost("https", "github.example.com"))
    }

    @Test
    fun picksNewestStableGkuiReleaseFromSharedRepository() {
        val releases = listOf(
            ReleaseSummary(0, "xgimi-lite-v2.23.0", draft = false, prerelease = false),
            ReleaseSummary(1, "gkui-v1.2.10", draft = true, prerelease = false),
            ReleaseSummary(2, "gkui-v1.2.9", draft = false, prerelease = false),
            ReleaseSummary(3, "gkui-v1.3.0", draft = false, prerelease = true),
            ReleaseSummary(4, "gkui-v1.2.8", draft = false, prerelease = false),
        )
        assertEquals(2, GkuiUpdatePolicy.newestStableIndex(releases))
        assertNull(GkuiUpdatePolicy.newestStableIndex(releases.take(2)))
    }

    @Test
    fun keepsUpdatingAfterAnOwnerRename() {
        val name = GkuiUpdatePolicy.expectedAssetName("1.3.0")
        assertTrue(GkuiUpdatePolicy.isTrustedAssetUrl(
            "https://github.com/new-nick/plezy-gkui/releases/download/gkui-v1.3.0/$name",
            "gkui-v1.3.0",
            name,
        ))
        assertFalse(GkuiUpdatePolicy.isTrustedAssetUrl(
            "https://github.com/new-nick/other-repo/releases/download/gkui-v1.3.0/$name",
            "gkui-v1.3.0",
            name,
        ))
        assertFalse(GkuiUpdatePolicy.isTrustedAssetUrl(
            "https://github.com/new-nick/plezy-gkui/releases/download/gkui-v1.2.9/$name",
            "gkui-v1.3.0",
            name,
        ))
        assertTrue(GkuiUpdatePolicy.isTrustedApiRedirect("https", "api.github.com"))
        assertFalse(GkuiUpdatePolicy.isTrustedApiRedirect("https", "example.com"))
    }

    @Test
    fun recognisesOnlyFinishedGkuiDownloads() {
        assertEquals("1.2.9", GkuiUpdatePolicy.versionFromAssetName("plezy-gkui-1.2.9-armeabi-v7a.apk"))
        assertNull(GkuiUpdatePolicy.versionFromAssetName("plezy-gkui-1.2.9-armeabi-v7a.apk.download"))
        assertNull(GkuiUpdatePolicy.versionFromAssetName("other.apk"))
    }
}
