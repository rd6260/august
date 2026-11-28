package com.rd6260.august

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.rd6260.august.youtube.YouTubeChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // First, so a crash on the Android side is written down and shown
        // on the next launch.
        CrashFiles.installCrashHandler(this)
        super.onCreate(savedInstanceState)
    }

    @Deprecated("The folder picker still answers here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (WhatsAppStickers.onResult(this, requestCode, resultCode, data)) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CrashFiles.register(this, flutterEngine.dartExecutor.binaryMessenger)
        // Song clips (C27, C28): NewPipe finds the stream (see youtube.dart).
        YouTubeChannel.register(flutterEngine.dartExecutor.binaryMessenger)
        // Over-the-air updates from GitHub Releases (lib/net/updater.dart).
        Updater.register(this, flutterEngine.dartExecutor.binaryMessenger)
        // The dev flavor's storage permission and profile restarts.
        DevStorage.register(this, flutterEngine.dartExecutor.binaryMessenger)
        // The sticker tray's WhatsApp tab: WhatsApp's sticker folder.
        WhatsAppStickers.register(this, flutterEngine.dartExecutor.binaryMessenger)
        // "Hide in recent apps" (C36): FLAG_SECURE blanks August in the
        // app switcher and blocks screenshots of it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "august/window")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // The widget, redrawn by home_widget's background engine
                    // (widget_refresh.dart). The app's own engine reads the
                    // picture back from the GPU in a way that comes out
                    // sheared on some phones; that one doesn't.
                    "redrawWidget" -> {
                        val intent = android.content.Intent(
                            this,
                            es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java,
                        )
                            .setAction("es.antonborri.home_widget.action.BACKGROUND")
                            .setData(android.net.Uri.parse("august://redraw"))
                        sendBroadcast(intent)
                        result.success(null)
                    }
                    "secure" -> {
                        val on = call.arguments as? Boolean ?: true
                        runOnUiThread {
                            if (on) {
                                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    // Settings › Notifications › Turn on, once Android
                    // stops asking: August's own notification settings.
                    "notificationSettings" -> {
                        val intent = android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
