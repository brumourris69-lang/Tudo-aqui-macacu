package br.com.tudoaquimacacu.tudo_aqui_macacu

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import java.io.FileInputStream

/** Per-app IPv4/IPv6 sink, without any forwarding. Android loopback stays local. */
class SearchLocalVpnService : VpnService() {
    companion object {
        @Volatile var active = false
        @Volatile var discardedPackets = 0L
        @JvmStatic fun isIsolated() = active
    }
    private var tunnel: ParcelFileDescriptor? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        check(packageName.endsWith(".searchlocal"))
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("local_isolation", "Isolamento local", NotificationManager.IMPORTANCE_LOW))
        startForeground(41, Notification.Builder(this, "local_isolation")
            .setContentTitle("Busca Local: rede externa bloqueada")
            .setSmallIcon(android.R.drawable.ic_lock_lock).build())
        if (!active) {
            tunnel = Builder().setSession("Macacu — somente emuladores locais")
                .addAllowedApplication(packageName)
                .addAddress("10.254.254.1", 32).addRoute("0.0.0.0", 0)
                .addAddress("fd00:ffff::1", 128).addRoute("::", 0)
                .addDnsServer("192.0.2.53").setBlocking(true).establish()
                ?: throw IllegalStateException("Unable to establish local isolation VPN")
            active = true
            Thread {
                try {
                    val input = FileInputStream(tunnel!!.fileDescriptor)
                    val buffer = ByteArray(32767)
                    while (active && input.read(buffer) >= 0) discardedPackets++
                } catch (_: Exception) {
                    if (active) Runtime.getRuntime().halt(0)
                } finally {
                    if (active) Runtime.getRuntime().halt(0)
                }
            }.start()
        }
        return START_NOT_STICKY
    }
    override fun onRevoke() { Runtime.getRuntime().halt(0) }
    override fun onDestroy() { Runtime.getRuntime().halt(0) }
}
