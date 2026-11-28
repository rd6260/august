package com.rd6260.august

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * The home screen widget: the doodle you both picked, as August drew it
 * (lib/platform/doodle_widget.dart), with who changed it last and when.
 * Tapping it opens that board.
 */
class DoodleWidget : HomeWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
    widgetData: SharedPreferences,
  ) {
    val path = widgetData.getString("doodle_path", null)
    val id = widgetData.getString("doodle_id", null)
    val caption = widgetData.getString("doodle_caption", null)
    val picture = path?.let { decode(it) }
    // A picture was promised but can't be read (being replaced right now):
    // keep showing the last good one rather than the empty state.
    if (path != null && picture == null) return
    val open = Uri.parse("august://doodle" + (id?.let { "?id=${Uri.encode(it)}" } ?: ""))

    for (widgetId in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.doodle_widget)
      if (picture != null) {
        views.setImageViewBitmap(R.id.doodle_image, picture)
        views.setViewVisibility(R.id.doodle_image, View.VISIBLE)
        views.setViewVisibility(R.id.doodle_empty, View.GONE)
        views.setTextViewText(R.id.doodle_caption, caption ?: "")
        views.setViewVisibility(
          R.id.doodle_caption,
          if (caption.isNullOrEmpty()) View.GONE else View.VISIBLE,
        )
      } else {
        views.setViewVisibility(R.id.doodle_image, View.GONE)
        views.setViewVisibility(R.id.doodle_caption, View.GONE)
        views.setViewVisibility(R.id.doodle_empty, View.VISIBLE)
      }
      views.setOnClickPendingIntent(
        R.id.doodle_root,
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, open),
      )
      // The caption ("You · 06:45") redraws it, without opening August.
      views.setOnClickPendingIntent(
        R.id.doodle_caption,
        HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("august://refresh")),
      )
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  /**
   * The picture, small enough to always reach the launcher (a widget's
   * bitmap goes over a ~1 MB channel): at most ~600 px, and RGB_565 since
   * it has no transparency, about 0.7 MB.
   */
  private fun decode(path: String): android.graphics.Bitmap? {
    val file = File(path)
    if (!file.exists()) return null
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, bounds)
    if (bounds.outWidth <= 0) return null
    var sample = 1
    while (bounds.outWidth / (sample * 2) >= 600) sample *= 2
    val options = BitmapFactory.Options().apply {
      inSampleSize = sample
      inPreferredConfig = android.graphics.Bitmap.Config.RGB_565
    }
    return try {
      BitmapFactory.decodeFile(path, options)
    } catch (_: Exception) {
      null
    }
  }
}
