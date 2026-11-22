package s21.campus_pass

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File

data class WidgetAppearance(
    val content: String = "logo",
    val background: Int = Color.BLACK,
    val foreground: Int = 0xFF8DF86B.toInt(),
) {
    val textColor: Int
        get() {
            fun linear(value: Int): Double {
                val channel = value / 255.0
                return if (channel <= .04045) channel / 12.92
                    else Math.pow((channel + .055) / 1.055, 2.4)
            }
            val luminance = .2126 * linear(Color.red(background)) +
                .7152 * linear(Color.green(background)) + .0722 * linear(Color.blue(background))
            return if (luminance > .179) Color.BLACK else Color.WHITE
        }

    fun message(): Map<String, Any> = mapOf(
        "content" to content,
        "background" to (background.toLong() and 0xFFFFFFFFL),
        "foreground" to (foreground.toLong() and 0xFFFFFFFFL),
    )

    fun colorQr(source: Bitmap): Bitmap {
        fun row(shift: Int): FloatArray {
            val low = (foreground ushr shift) and 255
            val high = (background ushr shift) and 255
            val scale = (high - low) / 255f
            return floatArrayOf(scale * .299f, scale * .587f, scale * .114f, 0f, low.toFloat())
        }
        val matrix = row(16) + row(8) + row(0) + floatArrayOf(0f, 0f, 0f, 0f, 255f)
        val opaque = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        Canvas(opaque).apply {
            drawColor(Color.WHITE)
            drawBitmap(source, 0f, 0f, null)
        }
        val result = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val paint = Paint().apply { colorFilter = ColorMatrixColorFilter(ColorMatrix(matrix)) }
        Canvas(result).drawBitmap(opaque, 0f, 0f, paint)
        opaque.recycle()
        return result
    }
}

object WidgetAppearanceStore {
    private fun file(context: Context) =
        AtomicFile(File(context.noBackupFilesDir, "widget-appearance.json"))

    @Synchronized
    fun read(context: Context): WidgetAppearance = try {
        val target = file(context)
        if (!target.baseFile.exists() || target.baseFile.length() > 4096) WidgetAppearance()
        else fromMessage(JSONObject(target.readFully().toString(Charsets.UTF_8)).let {
            mapOf("content" to it.optString("content"),
                "background" to it.optLong("background", 0xFF000000L),
                "foreground" to it.optLong("foreground", 0xFF8DF86BL))
        })
    } catch (_: Exception) {
        WidgetAppearance()
    }

    private fun fromMessage(value: Map<*, *>) = WidgetAppearance(
        content = if (value["content"] == "qr") "qr" else "logo",
        background = ((value["background"] as? Number)?.toInt() ?: Color.BLACK) or Color.BLACK,
        foreground = ((value["foreground"] as? Number)?.toInt() ?: 0xFF8DF86B.toInt()) or Color.BLACK,
    )

    @Synchronized
    fun save(context: Context, value: Map<*, *>) {
        val target = file(context)
        val stream = target.startWrite()
        try {
            stream.write(JSONObject(fromMessage(value).message()).toString().toByteArray(Charsets.UTF_8))
            target.finishWrite(stream)
        } catch (error: Exception) {
            target.failWrite(stream)
            throw error
        }
    }
}
