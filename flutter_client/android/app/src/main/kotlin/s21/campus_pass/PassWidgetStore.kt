package s21.campus_pass

import android.content.Context
import android.graphics.BitmapFactory
import android.util.AtomicFile
import android.util.Base64
import org.json.JSONObject
import java.io.File

data class StoredWidgetPass(
    val image: ByteArray,
    val expiresAt: Long,
    val expiresOn: Long?,
    val boostBrightness: Boolean,
    val scanSize: Double,
) {
    fun message(): Map<String, Any?> = mapOf(
        "image" to image, "expiresAt" to expiresAt, "expiresOn" to expiresOn,
        "boostBrightness" to boostBrightness, "scanSize" to scanSize,
    )
}

/** One atomic, app-private file. Never contains an account or an auth token. */
object PassWidgetStore {
    private val lock = Any()
    private fun file(context: Context) = AtomicFile(File(context.noBackupFilesDir, "widget-pass.json"))

    fun publish(context: Context, arguments: Map<*, *>) = synchronized(lock) {
        val image = arguments["image"] as? ByteArray ?: error("Missing QR image")
        val expiresAt = (arguments["expiresAt"] as? Number)?.toLong() ?: error("Missing expiry")
        require(image.size in 9..4 * 1024 * 1024)
        require(image.take(8) == listOf(137, 80, 78, 71, 13, 10, 26, 10).map { it.toByte() })
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(image, 0, image.size, bounds)
        require(bounds.outWidth in 1..4096 && bounds.outHeight in 1..4096)
        if (expiresAt <= System.currentTimeMillis()) {
            file(context).delete()
            return@synchronized
        }
        val json = JSONObject().apply {
            put("image", Base64.encodeToString(image, Base64.NO_WRAP))
            put("expiresAt", expiresAt)
            put("expiresOn", arguments["expiresOn"] ?: JSONObject.NULL)
            put("boostBrightness", arguments["boostBrightness"] != false)
            put("scanSize", ((arguments["scanSize"] as? Number)?.toDouble() ?: 1.0).coerceIn(.75, 1.0))
        }
        val target = file(context)
        val stream = target.startWrite()
        try {
            stream.write(json.toString().toByteArray(Charsets.UTF_8))
            target.finishWrite(stream)
        } catch (error: Exception) {
            target.failWrite(stream)
            throw error
        }
    }

    fun read(context: Context): StoredWidgetPass? = synchronized(lock) {
        try {
            val target = file(context)
            if (!target.baseFile.exists() || target.baseFile.length() > 6 * 1024 * 1024) return@synchronized null
            val json = JSONObject(target.readFully().toString(Charsets.UTF_8))
            val expiresAt = json.getLong("expiresAt")
            if (expiresAt <= System.currentTimeMillis()) {
                target.delete()
                return@synchronized null
            }
            StoredWidgetPass(
                Base64.decode(json.getString("image"), Base64.NO_WRAP), expiresAt,
                if (json.isNull("expiresOn")) null else json.getLong("expiresOn"),
                json.optBoolean("boostBrightness", true), json.optDouble("scanSize", 1.0).coerceIn(.75, 1.0),
            )
        } catch (_: Exception) {
            file(context).delete()
            null
        }
    }

    fun clear(context: Context) = synchronized(lock) { file(context).delete() }
}
