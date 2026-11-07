package s21.campus_pass

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Display
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast

/** A native overlay window. Never starts MainActivity or a Flutter engine. */
object QrOverlay {
    private val handler = Handler(Looper.getMainLooper())
    private var root: View? = null
    private var manager: WindowManager? = null
    private var application: Context? = null
    private var screenOff: BroadcastReceiver? = null
    private val timeout = Runnable {
        val context = application
        dismiss()
        if (context != null) PassWidgetProvider.updateAll(context)
    }

    fun dismiss() {
        handler.removeCallbacks(timeout)
        val view = root
        root = null
        if (view != null) runCatching { manager?.removeViewImmediate(view) }
        screenOff?.let { receiver -> runCatching { application?.unregisterReceiver(receiver) } }
        screenOff = null
        application = null
        manager = null
    }

    fun show(context: Context) {
        dismiss()
        val pass = PassWidgetStore.read(context)
        if (pass == null) {
            Toast.makeText(context, "Срок QR истёк. Получите новый код в приложении.", Toast.LENGTH_LONG).show()
            PassWidgetProvider.updateAll(context)
            return
        }
        if (context.getSystemService(KeyguardManager::class.java).isKeyguardLocked) return
        if (!Settings.canDrawOverlays(context)) {
            Toast.makeText(context, "Разрешите показ поверх экрана: Настройки пропуска → Виджет QR-кода", Toast.LENGTH_LONG).show()
            return
        }
        val display = context.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
        val visualContext = if (Build.VERSION.SDK_INT >= 30)
            context.createDisplayContext(display).createWindowContext(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null)
            else context
        val wm = visualContext.getSystemService(WindowManager::class.java)
        val density = visualContext.resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()
        val bounds = visualContext.resources.displayMetrics
        val edge = ((minOf(bounds.widthPixels, bounds.heightPixels) - dp(32)) * pass.scanSize).toInt()
        val bitmap = BitmapFactory.decodeByteArray(pass.image, 0, pass.image.size)
        if (bitmap == null) return
        val container = FrameLayout(visualContext).apply {
            setBackgroundColor(0xDD111318.toInt())
            contentDescription = "Увеличенный QR на рабочем столе"
            isFocusableInTouchMode = true
            setOnClickListener { dismiss() }
            setOnKeyListener { _, key, event ->
                if (key == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                    dismiss(); true
                } else false
            }
        }
        val image = ImageView(visualContext).apply {
            setImageBitmap(bitmap)
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = "QR-пропуск"
            setPadding(dp(20), dp(20), dp(20), dp(20))
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dp(24).toFloat()
            }
            setOnClickListener { /* Keep the image open while scanning. */ }
        }
        container.addView(image, FrameLayout.LayoutParams(edge, edge, Gravity.CENTER))
        val close = TextView(visualContext).apply {
            text = "✕"
            textSize = 28f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            contentDescription = "Закрыть QR"
            setOnClickListener { dismiss() }
        }
        container.addView(close, FrameLayout.LayoutParams(dp(48), dp(48), Gravity.TOP or Gravity.END).apply {
            topMargin = dp(24); rightMargin = dp(16)
        })
        if (Build.VERSION.SDK_INT >= 30) {
            container.setOnApplyWindowInsetsListener { view, insets ->
                val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars())
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
                insets
            }
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            title = "Campus Pass QR overlay"
            if (pass.boostBrightness) screenBrightness = 1f
        }
        try {
            wm.addView(container, params)
            root = container
            manager = wm
            application = context.applicationContext
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) = dismiss()
            }
            screenOff = receiver
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(receiver, IntentFilter(Intent.ACTION_SCREEN_OFF), Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(receiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
            }
            container.requestFocus()
            handler.postDelayed(timeout, minOf(120_000L, pass.expiresAt - System.currentTimeMillis()).coerceAtLeast(1))
        } catch (_: Exception) {
            dismiss()
            Toast.makeText(context, "Не удалось показать QR поверх экрана", Toast.LENGTH_LONG).show()
        }
    }
}
