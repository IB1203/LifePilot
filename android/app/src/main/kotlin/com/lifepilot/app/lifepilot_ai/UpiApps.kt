package com.lifepilot.app.lifepilot_ai

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import java.io.ByteArrayOutputStream

/** Lists installed apps that can open `upi://pay` links. */
object UpiApps {
    fun installed(context: Context): List<Map<String, Any>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay"))
        return pm.queryIntentActivities(intent, 0)
            .distinctBy { it.activityInfo.packageName }
            .filter { it.activityInfo.packageName != context.packageName }
            .map { info ->
                mapOf(
                    "package" to info.activityInfo.packageName,
                    "name" to info.loadLabel(pm).toString(),
                    "icon" to png(info.loadIcon(pm)),
                )
            }
            .sortedBy { (it["name"] as String).lowercase() }
    }

    private fun png(drawable: Drawable, size: Int = 96): ByteArray {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        } else {
            Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also {
                val canvas = Canvas(it)
                drawable.setBounds(0, 0, size, size)
                drawable.draw(canvas)
            }
        }
        return ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            it.toByteArray()
        }
    }
}
