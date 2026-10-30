package com.lifepilot.app.lifepilot_ai

import android.content.ClipData
import android.content.ActivityNotFoundException
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Same value as ClipDescription.EXTRA_IS_SENSITIVE (API 33).
private const val IS_SENSITIVE = "android.content.extra.IS_SENSITIVE"

// FlutterFragmentActivity is required by local_auth for the biometric prompt.
class MainActivity : FlutterFragmentActivity() {
    private var pendingUpi: MethodChannel.Result? = null
    private var pendingPermission: MethodChannel.Result? = null

    /** Xiaomi's app-list permission: "unsupported" on other phones. */
    private fun appListAccess(): String {
        try {
            packageManager.getPermissionInfo(GET_INSTALLED_APPS, 0)
        } catch (error: PackageManager.NameNotFoundException) {
            return "unsupported"
        }
        return if (checkSelfPermission(GET_INSTALLED_APPS) == PackageManager.PERMISSION_GRANTED) {
            "granted"
        } else {
            "denied"
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != APPS_PERMISSION_REQUEST) return
        val result = pendingPermission ?: return
        pendingPermission = null
        result.success(appListAccess() == "granted")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lifepilot/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setCapture" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        packageManager.setComponentEnabledSetting(
                            ComponentName(this, BankSmsReceiver::class.java),
                            if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                            PackageManager.DONT_KILL_APP,
                        )
                        getSharedPreferences(SmsQueue.PREFS, MODE_PRIVATE).edit()
                            .putBoolean(SmsQueue.HIDE_AMOUNTS, call.argument<Boolean>("hideAmounts") != false)
                            .apply()
                        result.success(null)
                    }
                    "pending" -> result.success(SmsQueue.pending(this))
                    "remove" -> {
                        SmsQueue.remove(this, call.argument<List<String>>("names") ?: emptyList())
                        result.success(null)
                    }
                    "launchTarget" -> {
                        val target = intent?.getStringExtra(OPEN_EXTRA)
                        intent?.removeExtra(OPEN_EXTRA)
                        result.success(target)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lifepilot/upi")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "apps" -> result.success(UpiApps.installed(this))
                    "appListAccess" -> result.success(appListAccess())
                    "requestAppListAccess" -> {
                        if (appListAccess() != "denied" || pendingPermission != null) {
                            result.success(appListAccess() == "granted")
                        } else {
                            pendingPermission = result
                            requestPermissions(arrayOf(GET_INSTALLED_APPS), APPS_PERMISSION_REQUEST)
                        }
                    }
                    "pay" -> pay(call.argument<String>("uri")!!, call.argument<String>("package"), result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lifepilot/security")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dataKey" -> try {
                        result.success(DeviceKey.dataKey(applicationContext))
                    } catch (error: Exception) {
                        result.error("key_unavailable", error.javaClass.simpleName, null)
                    }
                    "setSecure" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "copySensitive" -> {
                        val clip = ClipData.newPlainText("LifePilot", call.arguments as String)
                        // Android 13+ hides sensitive clips from the copy
                        // preview; older versions ignore the flag.
                        clip.description.extras = PersistableBundle().apply {
                            putBoolean(IS_SENSITIVE, true)
                        }
                        val clipboard =
                            getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(clip)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Opens a UPI app for the payment and reports back what it returns. */
    private fun pay(uri: String, packageName: String?, result: MethodChannel.Result) {
        if (pendingUpi != null) {
            result.error("busy", "A payment is already open", null)
            return
        }
        val view = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        // Without a chosen app, Android's own picker lists every UPI app,
        // even ones this app is not allowed to see.
        val intent = if (packageName != null) {
            view.setPackage(packageName)
        } else {
            Intent.createChooser(view, "Pay with")
        }
        // Only trust an empty result where the phone does not hide apps.
        if (packageName == null && appListAccess() != "denied" &&
            packageManager.queryIntentActivities(view, 0).isEmpty()
        ) {
            result.error("no_app", "No UPI app can open this payment", null)
            return
        }
        try {
            pendingUpi = result
            @Suppress("DEPRECATION")
            startActivityForResult(intent, UPI_REQUEST)
        } catch (error: ActivityNotFoundException) {
            pendingUpi = null
            result.error("no_app", "No UPI app can open this payment", null)
        }
    }

    @Deprecated("Uses the activity result of the UPI app")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != UPI_REQUEST) return
        val result = pendingUpi ?: return
        pendingUpi = null
        result.success(
            mapOf(
                "ok" to (resultCode == RESULT_OK),
                // Apps differ in where they put the response text.
                "response" to (data?.getStringExtra("response") ?: data?.dataString),
                "status" to data?.getStringExtra("Status"),
                "txnId" to data?.getStringExtra("txnId"),
            ),
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Lets a notification tap be read through "launchTarget".
        setIntent(intent)
    }

    companion object {
        private const val UPI_REQUEST = 4801
        private const val APPS_PERMISSION_REQUEST = 4804
        private const val GET_INSTALLED_APPS = "com.android.permission.GET_INSTALLED_APPS"
        const val OPEN_EXTRA = "lifepilot_open"
    }
}
