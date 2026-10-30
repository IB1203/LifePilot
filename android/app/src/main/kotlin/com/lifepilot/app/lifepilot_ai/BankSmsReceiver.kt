package com.lifepilot.app.lifepilot_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import org.json.JSONObject
import java.io.File
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Receives incoming SMS while "Read bank SMS as they arrive" is on (the
 * component is disabled otherwise). Bank-like messages are stored encrypted
 * until LifePilot opens and turns them into drafts; nothing is parsed into
 * records here and nothing leaves the phone.
 */
class BankSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        for ((address, messages) in parts.groupBy { it.originatingAddress ?: "" }) {
            val body = messages.joinToString("") { it.messageBody ?: "" }
            if (!SmsQueue.worthKeeping(body)) continue
            try {
                SmsQueue.add(context, address, body, messages.first().timestampMillis)
                SmsQueue.notify(context, body)
            } catch (error: Exception) {
                // Without the device key the message is skipped; the user can
                // still scan the inbox from the app.
            }
        }
    }
}

object SmsQueue {
    private const val FOLDER = "sms_queue"
    const val PREFS = "lifepilot_sms"
    const val HIDE_AMOUNTS = "hide_amounts"
    private const val CHANNEL = "lifepilot_bank_sms"
    private val MAGIC = byteArrayOf(0x4C, 0x50, 0x53, 0x31) // "LPS1"

    private val bankish = Regex(
        "(debited|credited|spent|withdrawn|sent|received|paid|refund|reversed|" +
            "a/c|account|bank|upi|kyc|card|blocked)",
        RegexOption.IGNORE_CASE,
    )
    private val signal = Regex("(rs[.:]?|inr|₹|\\d+\\.\\d{2}|kyc|blocked|http)", RegexOption.IGNORE_CASE)
    private val amount = Regex("(?:rs[.:]?|inr|₹)\\s*([\\d,]+(?:\\.\\d{1,2})?)", RegexOption.IGNORE_CASE)
    private val debit = Regex("\\b(debited|spent|sent|paid|withdrawn)", RegexOption.IGNORE_CASE)
    private val credit = Regex("\\b(credited|received|refund|reversed)", RegexOption.IGNORE_CASE)

    /** Keeps only messages that could be a transaction or a bank scam. */
    fun worthKeeping(body: String) = bankish.containsMatchIn(body) && signal.containsMatchIn(body)

    fun folder(context: Context) = File(context.filesDir, FOLDER)

    /** Writes one message sealed with the data key, in DataCipher's format. */
    fun add(context: Context, address: String, body: String, date: Long) {
        val json = JSONObject()
            .put("address", address)
            .put("body", body)
            .put("date", date)
            .toString()
            .toByteArray(Charsets.UTF_8)
        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(DeviceKey.dataKey(context), "AES"),
            GCMParameterSpec(128, nonce),
        )
        // Java appends the 16-byte tag to the cipher text, matching Dart.
        val sealed = MAGIC + nonce + cipher.doFinal(json)
        val dir = folder(context).apply { mkdirs() }
        val temporary = File(dir, "$date-${System.nanoTime()}.tmp")
        temporary.writeBytes(sealed)
        temporary.renameTo(File(dir, temporary.name.removeSuffix(".tmp") + ".lps"))
    }

    fun pending(context: Context): List<Map<String, Any>> =
        (folder(context).listFiles { file -> file.name.endsWith(".lps") } ?: emptyArray())
            .sortedBy { it.name }
            .map { mapOf("name" to it.name, "bytes" to it.readBytes()) }

    fun remove(context: Context, names: List<String>) {
        for (name in names) {
            if (name.contains('/') || !name.endsWith(".lps")) continue
            File(folder(context), name).delete()
        }
    }

    fun notify(context: Context, body: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Bank messages", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "New bank or UPI messages ready to review"
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                },
            )
        }
        val hide = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(HIDE_AMOUNTS, true)
        val value = amount.find(body)?.groupValues?.get(1)
        val kind = when {
            debit.containsMatchIn(body) -> "Debit"
            credit.containsMatchIn(body) -> "Credit"
            else -> null
        }
        val text = if (!hide && value != null && kind != null) {
            "$kind of ₹$value · tap to review"
        } else {
            "New bank message · tap to review"
        }
        val open = Intent(context, MainActivity::class.java)
            .putExtra(MainActivity.OPEN_EXTRA, "finance")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(
            context, 4803, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_lifepilot)
            .setContentTitle("LifePilot")
            .setContentText(text)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        manager.notify(4803, notification)
    }
}
