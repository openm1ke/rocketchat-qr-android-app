package s21.campus_pass

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "s21.campus_pass/widgets")
            .setMethodCallHandler { call, result ->
                try {
                    val manager = AppWidgetManager.getInstance(this)
                    when (call.method) {
                        "publish" -> {
                            PassWidgetStore.publish(this, call.arguments as Map<*, *>)
                            QrOverlay.dismiss()
                            PassWidgetProvider.updateAll(this)
                            result.success(null)
                        }
                        "clear" -> {
                            PassWidgetStore.clear(this)
                            QrOverlay.dismiss()
                            PassWidgetProvider.updateAll(this)
                            result.success(null)
                        }
                        "read" -> result.success(PassWidgetStore.read(this)?.message())
                        "capabilities" -> result.success(mapOf(
                            "platform" to "android", "supported" to true,
                            "pinSupported" to (Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported),
                            "overlayAllowed" to Settings.canDrawOverlays(this),
                            "installedCount" to manager.getAppWidgetIds(PassWidgetProvider.component(this)).size,
                        ))
                        "requestPin" -> result.success(Build.VERSION.SDK_INT >= 26 &&
                            manager.isRequestPinAppWidgetSupported &&
                            manager.requestPinAppWidget(PassWidgetProvider.component(this), null, null))
                        "requestOverlayPermission" -> {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("widget_storage", "Не удалось обновить виджет", null)
                }
            }
    }
}
