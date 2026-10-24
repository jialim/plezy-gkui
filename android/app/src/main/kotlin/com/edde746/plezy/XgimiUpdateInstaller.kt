package com.edde746.plezy

import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Opens Android's trusted package installer for a downloaded XGIMI APK. */
class XgimiUpdateInstaller(private val activity: FlutterActivity) {
  companion object {
    private const val CHANNEL = "com.plezy/xgimi_update"
    private const val TAG = "XgimiUpdateInstaller"
  }

  private var pendingApk: File? = null
  private var waitingForUnknownSourcesPermission = false

  fun attach(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      if (call.method != "installApk") {
        result.notImplemented()
        return@setMethodCallHandler
      }
      try {
        val path = call.argument<String>("path")
          ?: throw IllegalArgumentException("APK path is required")
        val apk = validatedCacheApk(path)
        XgimiApkVerifier.verify(activity.packageManager, activity.packageName, apk)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
          !activity.packageManager.canRequestPackageInstalls()
        ) {
          if (openUnknownSourcesSettings()) {
            pendingApk = apk
            waitingForUnknownSourcesPermission = true
            result.success("permission_requested")
          } else {
            // Some TV ROMs ship no settings screen for this. A session install
            // makes Android's own installer ask for the permission instead.
            installWithSession(apk)
            result.success("installer_started")
          }
        } else {
          launchInstaller(apk)
          result.success("installer_started")
        }
      } catch (error: Exception) {
        Log.w(TAG, "Could not start the update install", error)
        val code = if (error is SecurityException) "UPDATE_REJECTED" else "INSTALL_FAILED"
        result.error(code, "${error.javaClass.simpleName}: ${error.message ?: ""}", null)
      }
    }
  }

  /**
   * Called from PlezyActivity.onResume. The first resume after the settings
   * screen settles the request either way: a later, unrelated resume must not
   * pop an installer the viewer has forgotten about, and nothing here may
   * throw out of onResume.
   */
  fun onResume() {
    if (!waitingForUnknownSourcesPermission) return
    val apk = pendingApk
    pendingApk = null
    waitingForUnknownSourcesPermission = false
    if (apk == null || !apk.isFile) return
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
      !activity.packageManager.canRequestPackageInstalls()
    ) {
      return
    }
    try {
      launchInstaller(apk)
    } catch (error: Exception) {
      Log.w(TAG, "Could not open the package installer", error)
      // This installer only ships in the Chinese-first XGIMI build.
      Toast.makeText(activity, "无法打开安卓安装程序，请重新尝试更新。", Toast.LENGTH_LONG)
        .show()
    }
  }

  private fun validatedCacheApk(path: String): File {
    val apk = File(path).canonicalFile
    val cacheRoot = activity.cacheDir.canonicalFile
    if (!apk.path.startsWith(cacheRoot.path + File.separator) ||
      !apk.isFile ||
      !apk.name.endsWith(".apk", ignoreCase = true)
    ) {
      throw SecurityException("Refusing to install a file outside Plezy's update cache")
    }
    return apk
  }

  /**
   * Opens the screen where the viewer allows this app to install updates.
   * XGIMI and other TV ROMs may lack the per-app screen, so fall back to the
   * app list and the security settings. False when none of them exists.
   */
  private fun openUnknownSourcesSettings(): Boolean {
    val candidates = listOf(
      Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")),
      Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES),
      Intent(Settings.ACTION_SECURITY_SETTINGS),
    )
    for (intent in candidates) {
      try {
        activity.startActivity(intent)
        return true
      } catch (error: ActivityNotFoundException) {
        Log.w(TAG, "No settings screen for ${intent.action}")
      }
    }
    return false
  }

  private fun launchInstaller(apk: File) {
    val uri = FileProvider.getUriForFile(
      activity,
      "${activity.packageName}.fileprovider",
      apk
    )
    val intent = Intent(Intent.ACTION_VIEW).apply {
      setDataAndType(uri, "application/vnd.android.package-archive")
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    try {
      activity.startActivity(intent)
    } catch (error: ActivityNotFoundException) {
      // No activity takes an APK by URI on this ROM; the session API goes
      // straight to the system package installer.
      Log.w(TAG, "No APK viewer; installing through a PackageInstaller session")
      installWithSession(apk)
    }
  }

  private fun installWithSession(apk: File) {
    val installer = activity.packageManager.packageInstaller
    val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
      setAppPackageName(activity.packageName)
      setSize(apk.length())
    }
    val sessionId = installer.createSession(params)
    try {
      installer.openSession(sessionId).use { session ->
        apk.inputStream().use { input ->
          session.openWrite("update.apk", 0, apk.length()).use { output ->
            input.copyTo(output)
            session.fsync(output)
          }
        }
        // Mutable: the installer fills in the status and confirmation extras.
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
          (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
        val status = PendingIntent.getBroadcast(
          activity,
          sessionId,
          Intent(activity, XgimiInstallStatusReceiver::class.java),
          flags
        )
        session.commit(status.intentSender)
      }
    } catch (error: Exception) {
      installer.abandonSession(sessionId)
      throw error
    }
  }
}

/** Shows the system confirmation for a session install, or why it failed. */
class XgimiInstallStatusReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
      PackageInstaller.STATUS_PENDING_USER_ACTION -> {
        @Suppress("DEPRECATION")
        val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
        context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
      }
      PackageInstaller.STATUS_SUCCESS -> Unit
      else -> {
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        Log.w("XgimiUpdateInstaller", "Session install failed: $status $message")
        // This installer only ships in the Chinese-first XGIMI build.
        Toast.makeText(context, "更新安装失败（$status）：${message ?: ""}", Toast.LENGTH_LONG).show()
      }
    }
  }
}
