package com.rd6260.august

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * The sticker tray's WhatsApp tab (lib/platform/whatsapp_stickers.dart):
 * the stickers WhatsApp keeps as .webp files in the phone's storage. Android
 * only lets another app read that folder through the folder picker, so it's
 * picked once (the picker opens at it) and the access is kept.
 */
object WhatsAppStickers {
  private const val CHANNEL = "august/whatsapp"
  private const val PICK = 41
  private const val PREFS = "whatsapp_stickers"
  private const val KEY = "tree"
  private const val FOLDER = "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Stickers"

  private val io = Executors.newSingleThreadExecutor()
  private val main = Handler(Looper.getMainLooper())
  private var pending: MethodChannel.Result? = null

  fun register(activity: Activity, messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "hasFolder" -> result.success(tree(activity) != null)
        "pickFolder" -> pick(activity, result)
        "list" -> {
          val cache = call.argument<String>("cache") ?: return@setMethodCallHandler result.error("args", "cache", null)
          val max = call.argument<Int>("max") ?: 300
          io.execute {
            val out = try {
              list(activity, File(cache), max)
            } catch (e: Exception) {
              null
            }
            main.post { if (out == null) result.error("read", "Couldn't read the folder", null) else result.success(out) }
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  /** From MainActivity.onActivityResult. True when it was ours. */
  fun onResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != PICK) return false
    val result = pending ?: return true
    pending = null
    val uri = data?.data
    if (resultCode != Activity.RESULT_OK || uri == null) {
      result.success(false)
      return true
    }
    try {
      activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    } catch (_: SecurityException) {
      result.success(false)
      return true
    }
    activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, uri.toString()).apply()
    result.success(true)
    return true
  }

  private fun tree(context: Context): Uri? {
    val saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return null
    val uri = Uri.parse(saved)
    val kept = context.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
    return if (kept) uri else null
  }

  private fun pick(activity: Activity, result: MethodChannel.Result) {
    pending?.success(false)
    pending = result
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        putExtra(
          DocumentsContract.EXTRA_INITIAL_URI,
          DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:$FOLDER"),
        )
      }
    }
    try {
      activity.startActivityForResult(intent, PICK)
    } catch (e: Exception) {
      pending = null
      result.error("picker", "No folder picker", null)
    }
  }

  /**
   * The newest [max] stickers, copied into [cache] (once each) so Flutter
   * can show them as files: [{path, modified}], newest first.
   */
  private fun list(context: Context, cache: File, max: Int): List<Map<String, Any>> {
    val tree = tree(context) ?: return emptyList()
    val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
    val found = mutableListOf<Triple<String, String, Long>>() // id, name, modified
    context.contentResolver.query(
      children,
      arrayOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_LAST_MODIFIED,
      ),
      null, null, null,
    )?.use { c ->
      while (c.moveToNext()) {
        val name = c.getString(1) ?: continue
        if (!name.endsWith(".webp", ignoreCase = true)) continue
        found += Triple(c.getString(0), name, c.getLong(2))
      }
    }
    cache.mkdirs()
    return found.sortedByDescending { it.third }.take(max).mapNotNull { (id, name, modified) ->
      val out = File(cache, name)
      if (!out.exists() || out.lastModified() < modified) {
        try {
          val doc = DocumentsContract.buildDocumentUriUsingTree(tree, id)
          context.contentResolver.openInputStream(doc)?.use { input ->
            out.outputStream().use { input.copyTo(it) }
          } ?: return@mapNotNull null
          out.setLastModified(modified)
        } catch (_: Exception) {
          return@mapNotNull null
        }
      }
      mapOf("path" to out.path, "modified" to modified)
    }
  }
}
