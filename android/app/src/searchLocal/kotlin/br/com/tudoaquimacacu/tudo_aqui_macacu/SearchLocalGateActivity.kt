package br.com.tudoaquimacacu.tudo_aqui_macacu

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.graphics.Color
import android.view.Gravity
import android.util.TypedValue
import android.widget.TextView
import java.net.Socket
import java.net.InetSocketAddress
import java.util.concurrent.Executors

/** The only launcher: Flutter/plugins start after OS-level isolation. */
class SearchLocalGateActivity : Activity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val readinessWorker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "search-local-readiness").apply { isDaemon = true }
    }
    private var isolationStarted = false

    private fun trace(stage: String) {
        if (packageName.endsWith(".sparklocal") &&
            BuildConfig.DEBUG) {
            Log.i("SparkStartupNative", "stage=$stage elapsed_realtime_ms=${SystemClock.elapsedRealtime()}")
        }
    }

    override fun onCreate(state: Bundle?) {
        trace("gate_on_create")
        super.onCreate(state)
        val sparkLocal = packageName.endsWith(".sparklocal")
        setContentView(TextView(this).apply {
            text = if (sparkLocal) {
                "Tudo Aqui Macacu\n\nPreparando ambiente local seguro…"
            } else {
                "Preparando isolamento local…"
            }
            if (sparkLocal) {
                gravity = Gravity.CENTER
                setTextColor(Color.rgb(12, 47, 81))
                setBackgroundColor(Color.rgb(244, 248, 255))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            }
        })
        trace("gate_layout_ready")
        val permission = VpnService.prepare(this)
        if (permission != null) startActivityForResult(permission, 41) else startIsolation()
    }
    override fun onActivityResult(request: Int, result: Int, data: Intent?) {
        super.onActivityResult(request, result, data)
        if (request == 41 && result == RESULT_OK) startIsolation() else finish()
    }
    override fun onNewIntent(newIntent: Intent) {
        super.onNewIntent(newIntent)
        setIntent(newIntent)
    }
    private fun startIsolation() {
        if (isolationStarted) return
        isolationStarted = true
        trace("vpn_start_requested")
        val diagnosticsProxy = packageName.endsWith(".searchlocal") &&
            intent.action == Intent.ACTION_MAIN &&
            intent.getBooleanExtra("authHttpDiagnosticsProxy", false)
        val requiredPorts = if (packageName.endsWith(".sparklocal")) {
            listOf(9097, 8087)
        } else if (diagnosticsProxy) {
            listOf(9097, 8087, 5007, 9197)
        } else {
            listOf(9097, 8087, 5007)
        }
        startForegroundService(Intent(this, SearchLocalVpnService::class.java))
        readinessWorker.execute {
            var ready = false
            for (attempt in 0 until 200) {
                if (Thread.currentThread().isInterrupted) return@execute
                ready = SearchLocalVpnService.active && requiredPorts.all { port ->
                    try {
                        Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 150) }
                        true
                    } catch (_: Exception) { false }
                }
                if (ready) break
                try {
                    Thread.sleep(150)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return@execute
                }
            }
            if (ready) {
                trace("vpn_and_emulator_ports_ready")
                // FlutterEngine.createPackageContext() asks PackageManager for
                // this app's ApplicationInfo during MainActivity.onCreate().
                // On a cold Android 16 AVD that Binder call has blocked the
                // main thread long enough to generate a focus-loss ANR. Prime
                // the exact package metadata lookup here, off the UI thread,
                // before Flutter starts. Failure remains fail-closed.
                ready = try {
                    if (packageName != "br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal" &&
                        packageName != "br.com.tudoaquimacacu.tudo_aqui_macacu.prebeta" &&
                        packageName != "br.com.tudoaquimacacu.tudo_aqui_macacu.sparklocal") {
                        false
                    } else {
                        @Suppress("DEPRECATION")
                        packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                        true
                    }
                } catch (_: PackageManager.NameNotFoundException) {
                    false
                } catch (_: RuntimeException) {
                    false
                }
            }
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                if (ready) {
                    trace("gate_validation_complete")
                    val target = Intent(this@SearchLocalGateActivity, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_NEW_TASK
                        val link = safeIncomingContentLink()
                        if (link != null) {
                            action = Intent.ACTION_VIEW
                            data = link
                        }
                        if (diagnosticsProxy) putExtra("authHttpDiagnosticsProxy", true)
                    }
                    // Flutter's first engine/plugin/Firebase startup can take
                    // several seconds on an emulator. Retire this gate before
                    // MainActivity takes focus so its startup cannot leave a
                    // focus-loss event queued against the gate's main looper.
                    val appContext = applicationContext
                    finish()
                    mainHandler.post {
                        try {
                            trace("main_activity_launch")
                            appContext.startActivity(target)
                        } catch (error: RuntimeException) {
                            Log.e("SearchLocalGate", "Isolated app launch failed (${error.javaClass.simpleName})")
                        }
                    }
                    return@runOnUiThread
                }
                finish()
            }
        }
    }

    override fun onDestroy() {
        readinessWorker.shutdownNow()
        super.onDestroy()
    }

    private fun safeIncomingContentLink(): Uri? {
        if (intent.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        if (uri.scheme != "tudoaqui" || uri.host != "content" ||
            !uri.userInfo.isNullOrEmpty() || uri.port != -1 ||
            uri.query != null || uri.fragment != null ||
            uri.toString().length > 2048 || uri.pathSegments.size != 2) return null
        return uri
    }
}
