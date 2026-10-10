package com.edde746.plezy

import android.content.Intent
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
          !activity.packageManager.canRequestPackageInstalls()
        ) {
          pendingApk = apk
          waitingForUnknownSourcesPermission = true
          activity.startActivity(
            Intent(
              Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
              Uri.parse("package:${activity.packageName}")
            )
          )
          result.success("permission_requested")
        } else {
          launchInstaller(apk)
          result.success("installer_started")
        }
      } catch (error: Exception) {
        result.error("INSTALL_FAILED", error.message ?: error.javaClass.simpleName, null)
      }
    }
  }

  /**
   * Called from MainActivity.onResume. The first resume after the settings
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
      Toast.makeText(activity, "Android could not open the installer. Try the update again.", Toast.LENGTH_LONG)
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
    activity.startActivity(intent)
  }
}
