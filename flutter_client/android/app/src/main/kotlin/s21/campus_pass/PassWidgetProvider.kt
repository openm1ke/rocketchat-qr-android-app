package s21.campus_pass

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.KeyguardManager
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Bundle
import android.provider.Settings
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class PassWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = updateAll(context)

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) = updateAll(context)

    override fun onDisabled(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(expiryIntent(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_SHOW -> {
                if (context.getSystemService(KeyguardManager::class.java).isKeyguardLocked) return
                val pass = PassWidgetStore.read(context)
                if (pass != null) {
                    QrOverlay.show(context.applicationContext, pass)
                } else {
                    updateAll(context)
                    context.startActivity(openPassIntent(context))
                }
            }
            ACTION_EXPIRE, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> {
                if (PassWidgetStore.read(context) == null) QrOverlay.dismiss()
                updateAll(context)
            }
            else -> super.onReceive(context, intent)
        }
    }

    companion object {
        const val ACTION_SHOW = "s21.campus_pass.SHOW_WIDGET_QR"
        const val ACTION_OPEN = "s21.campus_pass.OPEN_WIDGET_PASS"
        private const val ACTION_EXPIRE = "s21.campus_pass.EXPIRE_WIDGET_QR"

        fun component(context: Context) = ComponentName(context, PassWidgetProvider::class.java)

        private fun openPassIntent(context: Context) =
            Intent(context, MainActivity::class.java).setAction(ACTION_OPEN)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

        private fun expiryIntent(context: Context) = PendingIntent.getBroadcast(
            context, 71, Intent(context, PassWidgetProvider::class.java).setAction(ACTION_EXPIRE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(component(context))
            val pass = PassWidgetStore.read(context)
            val appearance = WidgetAppearanceStore.read(context)
            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.pass_widget)
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                val open = if (pass == null) {
                    PendingIntent.getActivity(context, 73, openPassIntent(context), flags)
                } else {
                    PendingIntent.getBroadcast(
                        context, 72, Intent(context, PassWidgetProvider::class.java).setAction(ACTION_SHOW), flags,
                    )
                }
                views.setOnClickPendingIntent(R.id.widget_root, open)
                views.setInt(R.id.widget_root, "setBackgroundColor", appearance.background)
                views.setTextColor(R.id.widget_title, appearance.textColor)
                views.setTextColor(R.id.widget_status, appearance.textColor)
                views.setInt(R.id.widget_qr, "setBackgroundColor", appearance.background)
                views.setContentDescription(R.id.widget_qr,
                    if (appearance.content == "qr" && pass != null) "QR-пропуск" else "Логотип School 21")
                if (appearance.content == "qr" && pass != null) {
                    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(pass.image, 0, pass.image.size, options)
                    var sample = 1
                    while (maxOf(options.outWidth, options.outHeight) / sample > 512) sample *= 2
                    options.inJustDecodeBounds = false
                    options.inSampleSize = sample
                    val source = BitmapFactory.decodeByteArray(pass.image, 0, pass.image.size, options)
                    if (source != null) {
                        views.setImageViewBitmap(R.id.widget_qr, appearance.colorQr(source))
                    } else {
                        views.setImageViewResource(R.id.widget_qr, R.drawable.widget_logo)
                    }
                } else {
                    views.setImageViewResource(R.id.widget_qr, R.drawable.widget_logo)
                }
                if (pass != null) {
                    val status = if (!Settings.canDrawOverlays(context)) "Разрешите показ поверх экрана"
                        else if (pass.expiresOn != null) "До " + SimpleDateFormat("dd.MM", Locale.getDefault()).format(Date(pass.expiresOn))
                        else "Нажмите, чтобы увеличить"
                    views.setTextViewText(R.id.widget_status, status)
                } else {
                    views.setTextViewText(R.id.widget_status, "Обновите QR в приложении")
                }
                manager.updateAppWidget(id, views)
            }
            val alarm = context.getSystemService(AlarmManager::class.java)
            alarm.cancel(expiryIntent(context))
            if (pass != null && ids.isNotEmpty()) {
                // No exact-alarm permission: the timestamp is checked again on
                // every display and every click, even if Android defers this alarm.
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, pass.expiresAt, expiryIntent(context))
            }
        }
    }
}
