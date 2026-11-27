package com.rd6260.august

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The dev flavor's storage (lib/platform/data_home.dart): whether August may
 * use the phone's own storage, asking for it, and restarting August when it
 * switches profile. Unused by the prod flavor, which never asks.
 */
object DevStorage {
  private const val CHANNEL = "august/dev"

  fun register(activity: Activity, messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "allowed" -> result.success(allowed(activity))
        "ask" -> {
          ask(activity)
          result.success(null)
        }
        "restart" -> {
          restart(activity)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun allowed(context: Context): Boolean =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      Environment.isExternalStorageManager()
    } else {
      context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
        PackageManager.PERMISSION_GRANTED
    }

  private fun ask(activity: Activity) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      val intent = Intent(
        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
        Uri.parse("package:${activity.packageName}"),
      )
      try {
        activity.startActivity(intent)
      } catch (_: Exception) {
        activity.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
      }
    } else {
      activity.requestPermissions(
        arrayOf(
          Manifest.permission.READ_EXTERNAL_STORAGE,
          Manifest.permission.WRITE_EXTERNAL_STORAGE,
        ),
        7,
      )
    }
  }

  /** Opens August again in a moment, then ends this process. */
  private fun restart(activity: Activity) {
    val launch = activity.packageManager.getLaunchIntentForPackage(activity.packageName)
      ?: return
    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
    val pending = PendingIntent.getActivity(
      activity,
      8,
      launch,
      PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    val alarms = activity.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    alarms.set(AlarmManager.RTC, System.currentTimeMillis() + 300, pending)
    activity.finishAffinity()
    Runtime.getRuntime().exit(0)
  }
}
