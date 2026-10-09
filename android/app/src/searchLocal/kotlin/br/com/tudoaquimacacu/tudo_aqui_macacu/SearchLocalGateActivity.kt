package br.com.tudoaquimacacu.tudo_aqui_macacu

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.TextView
import java.net.Socket
import java.net.InetSocketAddress

/** The only launcher: Flutter/plugins start after OS-level isolation. */
class SearchLocalGateActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        setContentView(TextView(this).apply { text = "Preparando isolamento local…" })
        val permission = VpnService.prepare(this)
        if (permission != null) startActivityForResult(permission, 41) else startIsolation()
    }
    override fun onActivityResult(request: Int, result: Int, data: Intent?) {
        super.onActivityResult(request, result, data)
        if (request == 41 && result == RESULT_OK) startIsolation() else finish()
    }
    private fun startIsolation() {
        startForegroundService(Intent(this, SearchLocalVpnService::class.java))
        val handler = Handler(Looper.getMainLooper())
        var attempts = 0
        val wait = object : Runnable {
            override fun run() {
                Thread {
                    val ready = SearchLocalVpnService.active && listOf(9097, 8087, 5007).all { port ->
                        try {
                            Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 150) }
                            true
                        } catch (_: Exception) { false }
                    }
                    runOnUiThread {
                        if (ready && !isFinishing) {
                            val target = Intent(this@SearchLocalGateActivity, MainActivity::class.java)
                            intent.extras?.let { target.putExtras(it) }
                            startActivity(target)
                            finish()
                        } else if (++attempts < 200 && !isFinishing) handler.postDelayed(this, 150)
                        else finish()
                    }
                }.start()
            }
        }
        handler.post(wait)
    }
}
