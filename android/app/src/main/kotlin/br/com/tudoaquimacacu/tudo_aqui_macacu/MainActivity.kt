package br.com.tudoaquimacacu.tudo_aqui_macacu

import android.content.ActivityNotFoundException
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ApplicationInfo
import android.provider.Settings
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.LinkedHashSet

class MainActivity : FlutterActivity() {
    private val pendingContentLinks = LinkedHashSet<String>()
    private var contentLinksChannel: MethodChannel? = null
    private var pendingNotificationPermission: MethodChannel.Result? = null

    private fun traceSparkStartup(stage: String) {
        if (packageName.endsWith(".sparklocal") &&
            BuildConfig.DEBUG) {
            Log.i("SparkStartupNative", "stage=$stage elapsed_realtime_ms=${SystemClock.elapsedRealtime()}")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        traceSparkStartup("main_activity_on_create_enter")
        super.onCreate(savedInstanceState)
        traceSparkStartup("main_activity_on_create_ready")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        traceSparkStartup("flutter_engine_configure_enter")
        super.configureFlutterEngine(flutterEngine)
        traceSparkStartup("flutter_engine_plugins_ready")
        val contentLinks = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "macacu/content-links"
        )
        contentLinksChannel = contentLinks
        contentLinks.setMethodCallHandler { call, result ->
            if (call.method == "takePendingLinks") {
                val pending = pendingContentLinks.toList()
                pendingContentLinks.clear()
                result.success(pending)
            } else {
                result.notImplemented()
            }
        }
        rememberContentLink(intent?.dataString, notifyFlutter = false)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "macacu/public-share")
            .setMethodCallHandler { call, result ->
                if (call.method != "share") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val title = call.argument<String>("title")?.trim().orEmpty()
                val text = call.argument<String>("text")?.trim().orEmpty()
                if (title.isEmpty() || text.isEmpty()) {
                    result.error("INVALID_SHARE_CONTENT", "Conteúdo público inválido.", null)
                    return@setMethodCallHandler
                }
                try {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    startActivity(Intent.createChooser(intent, "Compartilhar $title"))
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.success(false)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "macacu/local-isolation")
            .setMethodCallHandler { call, result ->
                if (call.method == "environment") {
                    val local = packageName.endsWith(".searchlocal") ||
                        packageName.endsWith(".prebeta") || packageName.endsWith(".sparklocal")
                    val staging = packageName.endsWith(".staging")
                    val beta = packageName.endsWith(".beta")
                    val isolated = if (local) Class.forName("br.com.tudoaquimacacu.tudo_aqui_macacu.SearchLocalVpnService")
                        .getMethod("isIsolated").invoke(null) as Boolean else false
                    val appMetadata = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        packageManager.getApplicationInfo(
                            packageName,
                            PackageManager.ApplicationInfoFlags.of(
                                PackageManager.GET_META_DATA.toLong()
                            )
                        ).metaData
                    } else {
                        @Suppress("DEPRECATION")
                        packageManager.getApplicationInfo(
                            packageName,
                            PackageManager.GET_META_DATA
                        ).metaData
                    }
                    val expectedProject = if (staging) {
                        appMetadata?.getString("macacu.stagingFirebaseProjectId")
                    } else if (beta) {
                        appMetadata?.getString("macacu.betaFirebaseProjectId")
                    } else null
                    val webClientResource = if (beta) {
                        resources.getIdentifier("default_web_client_id", "string", packageName)
                    } else 0
                    val googleWebClientId = if (webClientResource != 0) {
                        getString(webClientResource)
                    } else null
                    val firebaseAppIdResource = if (beta) {
                        resources.getIdentifier("google_app_id", "string", packageName)
                    } else 0
                    val firebaseAppId = if (firebaseAppIdResource != 0) {
                        getString(firebaseAppIdResource)
                    } else null
                    val senderIdResource = if (beta) {
                        resources.getIdentifier("gcm_defaultSenderId", "string", packageName)
                    } else 0
                    val messagingSenderId = if (senderIdResource != 0) {
                        getString(senderIdResource)
                    } else null
                    result.success(mapOf("local" to local, "staging" to staging, "beta" to beta,
                        "isolated" to isolated, "package" to packageName,
                        "expectedProject" to expectedProject,
                        "googleWebClientId" to googleWebClientId,
                        "firebaseAppId" to firebaseAppId,
                        "messagingSenderId" to messagingSenderId))
                } else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "macacu/event-reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestNotificationPermission(result)
                    "notificationsEnabled" ->
                        result.success(EventReminderAlarm.notificationsEnabled(this))
                    "openNotificationSettings" -> openNotificationSettings(result)
                    "schedule" -> scheduleEventReminder(call, result)
                    "cancel" -> {
                        val id = call.argument<Int>("notificationId")
                        if (id == null || id <= 0) {
                            result.error("INVALID_REMINDER", "Lembrete inválido.", null)
                        } else {
                            EventReminderAlarm.cancel(this, id)
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        EventReminderAlarm.ensureChannel(this)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(EventReminderAlarm.notificationsEnabled(this))
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(EventReminderAlarm.notificationsEnabled(this))
            return
        }
        if (pendingNotificationPermission != null) {
            result.error("PERMISSION_PENDING", "A autorização já está em andamento.", null)
            return
        }
        pendingNotificationPermission = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    private fun openNotificationSettings(result: MethodChannel.Result) {
        val notificationSettings = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }
        try {
            startActivity(notificationSettings)
            result.success(true)
        } catch (_: android.content.ActivityNotFoundException) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName")
                    )
                )
                result.success(true)
            } catch (_: android.content.ActivityNotFoundException) {
                result.success(false)
            }
        }
    }

    private fun scheduleEventReminder(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("notificationId")
        val eventId = call.argument<String>("eventId")?.trim().orEmpty()
        val title = call.argument<String>("title")?.trim().orEmpty()
        val body = call.argument<String>("body")?.trim().orEmpty()
        val triggerAtMillis = call.argument<Number>("triggerAtMillis")?.toLong()
        if (id == null || id <= 0 || eventId.isEmpty() || eventId.length > 180 ||
            title.isEmpty() || title.length > 120 || body.isEmpty() || body.length > 180 ||
            triggerAtMillis == null || triggerAtMillis <= System.currentTimeMillis()) {
            result.error("INVALID_REMINDER", "Dados do lembrete inválidos ou horário passado.", null)
            return
        }
        if (!EventReminderAlarm.notificationsEnabled(this)) {
            result.success(false)
            return
        }
        result.success(EventReminderAlarm.schedule(this, id, eventId, title, body, triggerAtMillis))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) return
        val result = pendingNotificationPermission ?: return
        pendingNotificationPermission = null
        result.success(
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED &&
                EventReminderAlarm.notificationsEnabled(this)
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        rememberContentLink(intent.dataString)
    }

    private fun rememberContentLink(value: String?, notifyFlutter: Boolean = true) {
        if (value.isNullOrBlank() || value.length > 2048) return
        val uri = Uri.parse(value)
        if (uri.scheme != "tudoaqui" || uri.host != "content") return
        if (pendingContentLinks.size >= 8) {
            pendingContentLinks.remove(pendingContentLinks.first())
        }
        val added = pendingContentLinks.add(value)
        if (added && notifyFlutter) {
            contentLinksChannel?.invokeMethod("pendingContentLinks", null)
        }
    }

    companion object {
        private const val REQUEST_NOTIFICATIONS = 8021
    }
}
