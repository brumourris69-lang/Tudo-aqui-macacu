package br.com.tudoaquimacacu.tudo_aqui_macacu

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import org.json.JSONObject

internal object EventReminderAlarm {
    private const val CHANNEL_ID = "event_reminders"
    private const val CHANNEL_NAME = "Lembretes de eventos"
    private const val PREFERENCES = "macacu_event_reminders"
    private const val SCHEDULES_KEY = "schedules_v1"
    internal const val ACTION_FIRE = "br.com.tudoaquimacacu.EVENT_REMINDER"

    fun notificationsEnabled(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = manager.getNotificationChannel(CHANNEL_ID)
            if (channel?.importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        return true
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT)
        )
    }

    fun schedule(
        context: Context,
        notificationId: Int,
        eventId: String,
        title: String,
        body: String,
        triggerAtMillis: Long
    ): Boolean {
        if (triggerAtMillis <= System.currentTimeMillis()) return false
        ensureChannel(context)
        val record = JSONObject()
            .put("notificationId", notificationId)
            .put("eventId", eventId)
            .put("title", title)
            .put("body", body)
            .put("triggerAtMillis", triggerAtMillis)
            .toString()
        save(context, notificationId, record)
        val scheduled = scheduleAlarm(
            context,
            notificationId,
            eventId,
            title,
            body,
            triggerAtMillis
        )
        if (!scheduled) remove(context, notificationId)
        return scheduled
    }

    fun cancel(context: Context, notificationId: Int) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = pendingIntent(context, notificationId, null, null, null, PendingIntent.FLAG_NO_CREATE)
        if (pending != null) {
            manager.cancel(pending)
            pending.cancel()
        }
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(notificationId)
        remove(context, notificationId)
    }

    fun restoreAfterRestart(context: Context) {
        val records = read(context)
        val now = System.currentTimeMillis()
        records.toMap().forEach { (id, raw) ->
            try {
                val json = JSONObject(raw)
                val trigger = json.getLong("triggerAtMillis")
                if (trigger <= now) {
                    records.remove(id)
                } else {
                    scheduleAlarm(
                        context,
                        json.getInt("notificationId"),
                        json.getString("eventId"),
                        json.getString("title"),
                        json.getString("body"),
                        trigger
                    )
                }
            } catch (_: Exception) {
                records.remove(id)
            }
        }
        write(context, records)
    }

    private fun scheduleAlarm(
        context: Context,
        notificationId: Int,
        eventId: String,
        title: String,
        body: String,
        triggerAtMillis: Long
    ): Boolean {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = pendingIntent(context, notificationId, eventId, title, body, PendingIntent.FLAG_UPDATE_CURRENT)
            ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // Inexact idle-safe alarm avoids the special exact-alarm permission.
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pending)
            } else {
                manager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pending)
            }
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun pendingIntent(
        context: Context,
        notificationId: Int,
        eventId: String?,
        title: String?,
        body: String?,
        requestedFlags: Int
    ): PendingIntent? {
        val data = Uri.parse("macacu://event-reminder/$notificationId")
        val intent = Intent(context, EventReminderReceiver::class.java).apply {
            action = ACTION_FIRE
            this.data = data
            putExtra("notificationId", notificationId)
            if (eventId != null) putExtra("eventId", eventId)
            if (title != null) putExtra("title", title)
            if (body != null) putExtra("body", body)
        }
        var flags = requestedFlags
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, notificationId, intent, flags)
    }

    private fun save(context: Context, id: Int, raw: String) {
        val records = read(context)
        records[id.toString()] = raw
        write(context, records)
    }

    private fun remove(context: Context, id: Int) {
        val records = read(context)
        records.remove(id.toString())
        write(context, records)
    }

    private fun read(context: Context): MutableMap<String, String> {
        val set = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getStringSet(SCHEDULES_KEY, emptySet()) ?: emptySet()
        val values = mutableMapOf<String, String>()
        set.forEach { raw ->
            try {
                val json = JSONObject(raw)
                values[json.getInt("notificationId").toString()] = raw
            } catch (_: Exception) {
                // Drop malformed app-owned records; never use their data to schedule work.
            }
        }
        return values
    }

    private fun write(context: Context, records: Map<String, String>) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(SCHEDULES_KEY, records.values.toSet())
            .apply()
    }

    private fun post(context: Context, intent: Intent) {
        if (!notificationsEnabled(context)) return
        val id = intent.getIntExtra("notificationId", 0)
        val eventId = intent.getStringExtra("eventId") ?: return
        val title = intent.getStringExtra("title") ?: return
        val body = intent.getStringExtra("body") ?: return
        if (id <= 0 || eventId.isBlank() || title.isBlank() || body.isBlank()) return

        ensureChannel(context)
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("tudoaqui://content/event/${Uri.encode(eventId)}")
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            id,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()
        try {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(id, notification)
        } catch (_: SecurityException) {
            // The user can revoke notification permission after scheduling.
        }
    }

    internal fun fire(context: Context, intent: Intent) {
        post(context, intent)
        val id = intent.getIntExtra("notificationId", 0)
        if (id > 0) remove(context, id)
    }
}

class EventReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            EventReminderAlarm.ACTION_FIRE -> EventReminderAlarm.fire(context, intent)
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> EventReminderAlarm.restoreAfterRestart(context)
        }
    }
}
