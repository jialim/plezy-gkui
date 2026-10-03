package com.edde746.plezy

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

internal class UpdateException(val code: String, message: String) : Exception(message)

internal class GkuiUpdater(private val context: Context) {
    private val client: OkHttpClient by lazy {
        LegacyTls.createClient(context, readTimeoutSeconds = 120L)
            .newBuilder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .followRedirects(false)
            .followSslRedirects(false)
            .build()
    }

    fun check(): Map<String, Any> {
        val current = currentVersion()
        val release = fetchLatestRelease()
        return releaseMap(current, release)
    }

    fun downloadAndOpenInstaller(): Map<String, Any> {
        val current = currentVersion()
        val release = fetchLatestRelease()
        if (!GkuiUpdatePolicy.isNewer(release.version, current)) {
            return releaseMap(current, release)
        }
        val apk = download(release)
        verifyArchive(apk, release)
        openInstaller(apk)
        return releaseMap(current, release) + mapOf("installerOpened" to true)
    }

    private fun fetchLatestRelease(): GkuiRelease {
        val request = Request.Builder()
            .url(LATEST_RELEASE_API)
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", "Plezy-GKUI/${currentVersion()}")
            .build()
        client.newCall(request).execute().use { response ->
            if (response.code() != 200) {
                throw UpdateException("UPDATE_CHECK_FAILED", "GitHub returned HTTP ${response.code()}.")
            }
            val text = response.body()?.string()
                ?: throw UpdateException("UPDATE_CHECK_FAILED", "GitHub returned an empty response.")
            val json = JSONObject(text)
            if (json.optBoolean("draft") || json.optBoolean("prerelease")) {
                throw UpdateException("UPDATE_INVALID_RELEASE", "The latest release is not a stable GKUI build.")
            }
            val tag = json.optString("tag_name")
            val version = GkuiUpdatePolicy.versionFromTag(tag)
                ?: throw UpdateException("UPDATE_INVALID_RELEASE", "The latest release tag is not a GKUI version.")
            val expectedName = GkuiUpdatePolicy.expectedAssetName(version)
            val assets = json.optJSONArray("assets")
                ?: throw UpdateException("UPDATE_INVALID_RELEASE", "The release contains no APK.")
            var asset: JSONObject? = null
            for (index in 0 until assets.length()) {
                val candidate = assets.optJSONObject(index) ?: continue
                if (candidate.optString("name") == expectedName) {
                    asset = candidate
                    break
                }
            }
            val selected = asset
                ?: throw UpdateException("UPDATE_INVALID_RELEASE", "The ARMv7 GKUI APK is missing.")
            val assetUrl = selected.optString("browser_download_url")
            if (!GkuiUpdatePolicy.isTrustedAssetUrl(assetUrl, tag, expectedName)) {
                throw UpdateException("UPDATE_INVALID_RELEASE", "The release APK address is not trusted.")
            }
            val digest = GkuiUpdatePolicy.normalizedDigest(selected.optString("digest"))
                ?: throw UpdateException("UPDATE_INVALID_RELEASE", "The release APK has no valid SHA-256 digest.")
            val size = selected.optLong("size", -1L)
            if (size !in 1..MAX_APK_BYTES) {
                throw UpdateException("UPDATE_INVALID_RELEASE", "The release APK size is invalid.")
            }
            return GkuiRelease(
                version = version,
                tag = tag,
                assetName = expectedName,
                assetUrl = assetUrl,
                assetSize = size,
                sha256 = digest,
                releaseUrl = json.optString("html_url"),
            )
        }
    }

    private fun download(release: GkuiRelease): File {
        val cacheRoot = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            context.externalCacheDir ?: throw UpdateException(
                "UPDATE_STORAGE_FAILED",
                "External cache is unavailable, so Android cannot access the downloaded installer.",
            )
        } else {
            context.externalCacheDir ?: context.cacheDir
        }
        val directory = File(cacheRoot, "updates")
        if (!directory.exists() && !directory.mkdirs()) {
            throw UpdateException("UPDATE_STORAGE_FAILED", "Plezy could not create its update folder.")
        }
        directory.listFiles()?.forEach { file ->
            if (file.isFile && file.name != release.assetName) file.delete()
        }
        val target = File(directory, release.assetName)
        val temporary = File(directory, "${release.assetName}.download")
        temporary.delete()
        target.delete()

        var url = release.assetUrl
        for (redirect in 0..MAX_REDIRECTS) {
            val parsed = HttpUrl.parse(url)
                ?: throw UpdateException("UPDATE_DOWNLOAD_FAILED", "The APK download address is invalid.")
            if (!GkuiUpdatePolicy.isTrustedDownloadHost(parsed.scheme(), parsed.host())) {
                throw UpdateException("UPDATE_DOWNLOAD_FAILED", "The APK download host is not trusted.")
            }
            val request = Request.Builder()
                .url(parsed)
                .header("Accept", "application/octet-stream")
                .header("User-Agent", "Plezy-GKUI/${currentVersion()}")
                .build()
            client.newCall(request).execute().use { response ->
                if (response.code() in 300..399) {
                    val location = response.header("Location")
                        ?: throw UpdateException("UPDATE_DOWNLOAD_FAILED", "GitHub returned an empty redirect.")
                    url = response.request().url().resolve(location)?.toString()
                        ?: throw UpdateException("UPDATE_DOWNLOAD_FAILED", "GitHub returned an invalid redirect.")
                    return@use
                }
                if (response.code() != 200) {
                    throw UpdateException("UPDATE_DOWNLOAD_FAILED", "APK download returned HTTP ${response.code()}.")
                }
                val body = response.body()
                    ?: throw UpdateException("UPDATE_DOWNLOAD_FAILED", "APK download returned no data.")
                val declared = body.contentLength()
                if (declared > MAX_APK_BYTES || (declared >= 0 && declared != release.assetSize)) {
                    throw UpdateException("UPDATE_DOWNLOAD_FAILED", "APK download size does not match the release.")
                }
                val digest = MessageDigest.getInstance("SHA-256")
                var bytes = 0L
                body.byteStream().use { input ->
                    FileOutputStream(temporary).use { output ->
                        val buffer = ByteArray(32 * 1024)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            bytes += count
                            if (bytes > MAX_APK_BYTES) {
                                throw UpdateException("UPDATE_DOWNLOAD_FAILED", "APK download exceeded the size limit.")
                            }
                            digest.update(buffer, 0, count)
                            output.write(buffer, 0, count)
                        }
                        output.fd.sync()
                    }
                }
                val actualDigest = digest.digest().joinToString("") { byte -> "%02x".format(byte) }
                if (bytes != release.assetSize || actualDigest != release.sha256) {
                    temporary.delete()
                    throw UpdateException("UPDATE_VERIFY_FAILED", "The downloaded APK failed its SHA-256 check.")
                }
                if (!temporary.renameTo(target)) {
                    temporary.delete()
                    throw UpdateException("UPDATE_STORAGE_FAILED", "Plezy could not finish saving the update.")
                }
                return target
            }
        }
        temporary.delete()
        throw UpdateException("UPDATE_DOWNLOAD_FAILED", "GitHub returned too many redirects.")
    }

    @Suppress("DEPRECATION")
    private fun verifyArchive(apk: File, release: GkuiRelease) {
        val archive = context.packageManager.getPackageArchiveInfo(
            apk.absolutePath,
            PackageManager.GET_SIGNATURES,
        ) ?: throw UpdateException("UPDATE_VERIFY_FAILED", "Android could not read the downloaded APK.")
        if (archive.packageName != context.packageName || archive.versionName != release.version) {
            apk.delete()
            throw UpdateException("UPDATE_VERIFY_FAILED", "The downloaded APK is not the expected Plezy GKUI version.")
        }
        val installed = context.packageManager.getPackageInfo(
            context.packageName,
            PackageManager.GET_SIGNATURES,
        )
        val installedCertificates = installed.signatures.orEmpty().map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).toList()
        }
        val updateCertificates = archive.signatures.orEmpty().map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).toList()
        }
        if (installedCertificates.isEmpty() || installedCertificates.none(updateCertificates::contains)) {
            apk.delete()
            throw UpdateException("UPDATE_VERIFY_FAILED", "The downloaded APK is not signed with this installation's certificate.")
        }
    }

    private fun openInstaller(apk: File) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()
        ) {
            context.startActivity(Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            throw UpdateException(
                "UPDATE_PERMISSION_REQUIRED",
                "Allow Plezy GKUI to install updates, then tap Check now again.",
            )
        }
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
        } else {
            Uri.fromFile(apk)
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, APK_MIME)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        if (intent.resolveActivity(context.packageManager) == null) {
            throw UpdateException("UPDATE_INSTALLER_MISSING", "This head unit has no APK installer.")
        }
        context.startActivity(intent)
    }

    @Suppress("DEPRECATION")
    private fun currentVersion(): String =
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0.0.0"

    private fun releaseMap(current: String, release: GkuiRelease): Map<String, Any> = linkedMapOf(
        "available" to GkuiUpdatePolicy.isNewer(release.version, current),
        "currentVersion" to current,
        "latestVersion" to release.version,
        "releaseUrl" to release.releaseUrl,
        "assetName" to release.assetName,
        "assetSize" to release.assetSize,
    )

    companion object {
        private const val LATEST_RELEASE_API =
            "https://api.github.com/repos/jialim/plezy-gkui/releases/latest"
        private const val APK_MIME = "application/vnd.android.package-archive"
        private const val MAX_APK_BYTES = 100L * 1024L * 1024L
        private const val MAX_REDIRECTS = 5
    }
}
