package com.edde746.plezy

import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import java.io.File
import java.security.MessageDigest

/**
 * Checks a downloaded update before Android's installer sees it: same package
 * as this app, signed with this installation's certificate. Android would
 * reject a mismatched signature anyway, but only after the viewer confirmed
 * an install that then fails with a generic "App not installed".
 */
internal object XgimiApkVerifier {
  fun verify(packageManager: PackageManager, installedPackage: String, apk: File) {
    val archive = archiveInfo(packageManager, apk.path)
      ?: throw SecurityException("Android could not read the downloaded update.")
    if (archive.packageName != installedPackage) {
      throw SecurityException("The downloaded update is for a different app (${archive.packageName}).")
    }
    val installed = certificateDigests(installedInfo(packageManager, installedPackage))
    val update = certificateDigests(archive)
    if (!sharesSigner(installed, update)) {
      throw SecurityException("The downloaded update is not signed with this installation's key.")
    }
  }

  /** True when the update carries at least one of the installed certificates. */
  fun sharesSigner(installed: List<String>, update: List<String>): Boolean =
    installed.isNotEmpty() && installed.any(update::contains)

  fun digest(certificate: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(certificate).joinToString("") { "%02x".format(it) }

  @Suppress("DEPRECATION")
  private fun archiveInfo(packageManager: PackageManager, path: String): PackageInfo? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      val info = packageManager.getPackageArchiveInfo(path, PackageManager.GET_SIGNING_CERTIFICATES)
      if (info?.signingInfo != null) return info
    }
    return packageManager.getPackageArchiveInfo(path, PackageManager.GET_SIGNATURES)
  }

  @Suppress("DEPRECATION")
  private fun installedInfo(packageManager: PackageManager, packageName: String): PackageInfo =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
    } else {
      packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
    }

  @Suppress("DEPRECATION")
  private fun certificateDigests(info: PackageInfo): List<String> {
    val signatures: Array<Signature>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && info.signingInfo != null) {
      val signing = info.signingInfo!!
      if (signing.hasMultipleSigners()) signing.apkContentsSigners else signing.signingCertificateHistory
    } else {
      info.signatures
    }
    return signatures.orEmpty().map { digest(it.toByteArray()) }
  }
}
