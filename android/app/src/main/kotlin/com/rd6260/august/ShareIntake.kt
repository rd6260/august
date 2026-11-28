package com.rd6260.august

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Photos and videos shared to August from another app (the gallery's share
 * sheet). They're copied into August's cache, since the sender's links to
 * them don't last, then handed to lib/app/share_intake.dart, which opens
 * the preview to send them.
 */
object ShareIntake {
  private const val CHANNEL = "august/share"
  private val io = Executors.newSingleThreadExecutor()
  private val main = Handler(Looper.getMainLooper())
  private var channel: MethodChannel? = null
  private val pending = mutableListOf<Map<String, String>>()

  fun register(messenger: BinaryMessenger) {
    channel = MethodChannel(messenger, CHANNEL).also {
      it.setMethodCallHandler { call, result ->
        when (call.method) {
          // What's arrived and not taken yet; taking it clears it.
          "take" -> {
            result.success(pending.toList())
            pending.clear()
          }
          else -> result.notImplemented()
        }
      }
    }
  }

  /** From onCreate and onNewIntent: a share, if this intent is one. */
  fun handle(activity: Activity, intent: Intent?) {
    if (intent == null) return
    val action = intent.action
    if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
    val uris = streams(intent)
    // Taken: a rotation or a return to August doesn't share it again.
    intent.action = null
    if (uris.isEmpty()) return
    val fallback = intent.type
    io.execute {
      val dir = File(activity.cacheDir, "shared").apply { mkdirs() }
      val items = uris.mapNotNull { uri -> copy(activity, uri, fallback, dir) }
      main.post {
        if (items.isEmpty()) return@post
        pending += items
        channel?.invokeMethod("shared", null)
      }
    }
  }

  @Suppress("DEPRECATION")
  private fun streams(intent: Intent): List<Uri> = when (intent.action) {
    Intent.ACTION_SEND ->
      listOfNotNull(
        if (Build.VERSION.SDK_INT >= 33) {
          intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
          intent.getParcelableExtra(Intent.EXTRA_STREAM)
        },
      )
    else ->
      (if (Build.VERSION.SDK_INT >= 33) {
        intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
      } else {
        intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
      }) ?: emptyList()
  }

  private fun copy(activity: Activity, uri: Uri, fallback: String?, dir: File): Map<String, String>? {
    val mime = activity.contentResolver.getType(uri) ?: fallback ?: return null
    if (!mime.startsWith("image/") && !mime.startsWith("video/")) return null
    val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
      ?: if (mime.startsWith("video/")) "mp4" else "jpg"
    val out = File(dir, "${UUID.randomUUID()}.$ext")
    return try {
      activity.contentResolver.openInputStream(uri)?.use { input ->
        out.outputStream().use { input.copyTo(it) }
      } ?: return null
      mapOf("path" to out.path, "mime" to mime)
    } catch (_: Exception) {
      out.delete()
      null
    }
  }
}
