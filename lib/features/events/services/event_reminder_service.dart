import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/public_event.dart';
import '../utils/city_calendar_date.dart';

enum EventReminderLead {
  oneHour(Duration(hours: 1), '1 hora antes'),
  oneDay(Duration(days: 1), '1 dia antes');

  const EventReminderLead(this.duration, this.label);

  final Duration duration;
  final String label;

  static EventReminderLead? fromHours(int value) => switch (value) {
    1 => EventReminderLead.oneHour,
    24 => EventReminderLead.oneDay,
    _ => null,
  };
}

enum EventReminderResult {
  scheduled,
  disabledGlobally,
  permissionDenied,
  timePassed,
  invalidEventTime,
  unsupportedPlatform,
  failed,
}

class EventReminderRequest {
  const EventReminderRequest({
    required this.notificationId,
    required this.eventId,
    required this.title,
    required this.body,
    required this.triggerAtUtc,
  });

  final int notificationId;
  final String eventId;
  final String title;
  final String body;
  final DateTime triggerAtUtc;
}

class EventReminderSetting {
  const EventReminderSetting({
    required this.eventId,
    required this.title,
    required this.lead,
    required this.triggerAtUtc,
    required this.paused,
    required this.cancellationPending,
    required this.removalPending,
  });

  final String eventId;
  final String title;
  final EventReminderLead lead;
  final DateTime triggerAtUtc;
  final bool paused;
  final bool cancellationPending;
  final bool removalPending;
}

abstract interface class EventReminderPlatform {
  Future<bool> requestPermission();
  Future<bool> notificationsEnabled();
  Future<bool> openNotificationSettings();
  Future<bool> schedule(EventReminderRequest request);
  Future<void> cancel(int notificationId);
}

class _MethodChannelEventReminderPlatform implements EventReminderPlatform {
  static const _channel = MethodChannel('macacu/event-reminders');

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<bool> notificationsEnabled() async =>
      await _channel.invokeMethod<bool>('notificationsEnabled') ?? false;

  @override
  Future<bool> openNotificationSettings() async =>
      await _channel.invokeMethod<bool>('openNotificationSettings') ?? false;

  @override
  Future<bool> schedule(EventReminderRequest request) async =>
      await _channel.invokeMethod<bool>('schedule', {
        'notificationId': request.notificationId,
        'eventId': request.eventId,
        'title': request.title,
        'body': request.body,
        'triggerAtMillis': request.triggerAtUtc.millisecondsSinceEpoch,
      }) ??
      false;

  @override
  Future<void> cancel(int notificationId) =>
      _channel.invokeMethod<void>('cancel', {'notificationId': notificationId});
}

/// One reminder per account and event, persisted and scheduled on-device.
class EventReminderService {
  EventReminderService({
    EventReminderPlatform? platform,
    bool? isAndroid,
    bool? isIOS,
  }) : _platform = platform ?? _MethodChannelEventReminderPlatform(),
       _supported =
           isAndroid ??
           isIOS ??
           (defaultTargetPlatform == TargetPlatform.android ||
               defaultTargetPlatform == TargetPlatform.iOS);

  static final instance = EventReminderService();

  static const _storagePrefix = 'macacu.event-reminders.v1.';
  final EventReminderPlatform _platform;
  final bool _supported;

  bool get supported => _supported;

  Future<bool> notificationsEnabled() =>
      _supported ? _platform.notificationsEnabled() : Future.value(false);

  Future<bool> openNotificationSettings() =>
      _supported ? _platform.openNotificationSettings() : Future.value(false);

  Future<bool> remindersEnabled(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledStorageKey(uid)) ?? true;
  }

  Future<List<EventReminderSetting>> reminderSettings(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final records = _read(prefs, uid);
    return records.entries
        .map(
          (entry) => EventReminderSetting(
            eventId: entry.key,
            title: entry.value.title,
            lead: entry.value.lead,
            triggerAtUtc: entry.value.triggerAtUtc,
            paused: entry.value.paused,
            cancellationPending: entry.value.cancelPending,
            removalPending: entry.value.removePending,
          ),
        )
        .toList(growable: false)
      ..sort((left, right) => left.triggerAtUtc.compareTo(right.triggerAtUtc));
  }

  /// A global opt-out pauses alarms but keeps each event selection for later.
  Future<void> setRemindersEnabled(String uid, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledStorageKey(uid), enabled);
    if (enabled) return;
    final records = _read(prefs, uid);
    for (final entry in records.entries.toList(growable: false)) {
      try {
        await _platform.cancel(entry.value.notificationId);
        if (entry.value.removePending) {
          records.remove(entry.key);
        } else {
          records[entry.key] = entry.value.copyWith(
            paused: true,
            cancelPending: false,
          );
        }
      } catch (_) {
        records[entry.key] = entry.value.copyWith(
          paused: true,
          cancelPending: true,
        );
      }
    }
    await _write(prefs, uid, records);
  }

  Future<EventReminderResult> activate({
    required String uid,
    required PublicEvent event,
    required EventReminderLead lead,
    DateTime? now,
  }) async {
    if (!_supported) return EventReminderResult.unsupportedPlatform;
    if (uid.trim().isEmpty || event.id.trim().isEmpty) {
      return EventReminderResult.failed;
    }
    final trigger = eventReminderAtUtc(event, lead, now: now);
    if (trigger == null) {
      return eventStartAtUtc(event) == null
          ? EventReminderResult.invalidEventTime
          : EventReminderResult.timePassed;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final records = _read(prefs, uid);
      final existing = records[event.id];
      final notificationId =
          existing?.notificationId ?? _notificationId(uid, event.id, prefs);
      final request = _request(notificationId, event, lead, trigger);
      if (!await remindersEnabled(uid)) {
        records[event.id] = _ReminderRecord(
          notificationId: notificationId,
          lead: lead,
          triggerAtUtc: trigger,
          title: request.title,
          body: request.body,
          paused: true,
        );
        try {
          await _platform.cancel(notificationId);
        } catch (_) {
          records[event.id] = records[event.id]!.copyWith(cancelPending: true);
        }
        await _write(prefs, uid, records);
        return EventReminderResult.disabledGlobally;
      }
      if (!await _platform.requestPermission()) {
        records[event.id] = _ReminderRecord(
          notificationId: notificationId,
          lead: lead,
          triggerAtUtc: trigger,
          title: request.title,
          body: request.body,
          paused: true,
        );
        try {
          await _platform.cancel(notificationId);
        } catch (_) {
          records[event.id] = records[event.id]!.copyWith(cancelPending: true);
        }
        await _write(prefs, uid, records);
        return EventReminderResult.permissionDenied;
      }
      records[event.id] = _ReminderRecord(
        notificationId: notificationId,
        lead: lead,
        triggerAtUtc: trigger,
        title: request.title,
        body: request.body,
      );
      if (!await _write(prefs, uid, records)) return EventReminderResult.failed;
      var scheduled = false;
      try {
        scheduled = await _platform.schedule(request);
      } catch (_) {
        scheduled = false;
      }
      if (!scheduled) {
        try {
          await _platform.cancel(notificationId);
          records.remove(event.id);
        } catch (_) {
          records[event.id] = records[event.id]!.copyWith(
            paused: true,
            cancelPending: true,
          );
        }
        await _write(prefs, uid, records);
        return EventReminderResult.failed;
      }
      return EventReminderResult.scheduled;
    } on PlatformException {
      return EventReminderResult.failed;
    } catch (_) {
      return EventReminderResult.failed;
    }
  }

  Future<EventReminderLead?> leadFor(String uid, String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs, uid)[eventId]?.lead;
  }

  Future<bool> hasReminders(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs, uid).isNotEmpty;
  }

  String _enabledStorageKey(String uid) =>
      '$_storagePrefix${base64Url.encode(utf8.encode(uid))}.enabled';

  /// Cancels one account's alarms on logout while retaining its local choices.
  Future<void> pauseUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final records = _read(prefs, uid);
    for (final entry in records.entries.toList(growable: false)) {
      try {
        await _platform.cancel(entry.value.notificationId);
        if (entry.value.removePending) {
          records.remove(entry.key);
        } else {
          records[entry.key] = entry.value.copyWith(
            paused: true,
            cancelPending: false,
          );
        }
      } catch (_) {
        records[entry.key] = entry.value.copyWith(
          paused: true,
          cancelPending: true,
        );
      }
    }
    await _write(prefs, uid, records);
  }

  Future<void> cancel(String uid, String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final records = _read(prefs, uid);
    final removed = records.remove(eventId);
    if (removed == null) return;
    try {
      await _platform.cancel(removed.notificationId);
    } catch (_) {
      records[eventId] = removed.copyWith(
        paused: true,
        cancelPending: true,
        removePending: true,
      );
      await _write(prefs, uid, records);
      rethrow;
    }
    await _write(prefs, uid, records);
  }

  Future<void> cancelRemovedFromAgenda(
    String uid,
    Set<String> savedEventIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final records = _read(prefs, uid);
    final removed = records.entries
        .where((entry) => !savedEventIds.contains(entry.key))
        .toList(growable: false);
    for (final entry in removed) {
      try {
        await _platform.cancel(entry.value.notificationId);
        records.remove(entry.key);
      } catch (_) {
        records[entry.key] = entry.value.copyWith(
          paused: true,
          cancelPending: true,
          removePending: true,
        );
      }
    }
    if (removed.isNotEmpty) await _write(prefs, uid, records);
  }

  Future<void> clearUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final records = _read(prefs, uid);
    final pending = <String, _ReminderRecord>{};
    for (final entry in records.entries) {
      try {
        await _platform.cancel(entry.value.notificationId);
      } catch (_) {
        // Keep failed cancellations to retry when the app starts again.
        pending[entry.key] = entry.value.copyWith(
          paused: true,
          cancelPending: true,
          removePending: true,
        );
      }
    }
    if (pending.isEmpty) {
      await prefs.remove(_storageKey(uid));
    } else {
      await _write(prefs, uid, pending);
    }
  }

  /// Strict variant for account deletion: leave the account active if a
  /// scheduled local reminder cannot be canceled, so deletion can be retried.
  Future<void> clearUserForAccountDeletion(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final records = _read(prefs, uid);
    for (final record in records.values) {
      await _platform.cancel(record.notificationId);
    }
    await prefs.remove(_storageKey(uid));
    await prefs.remove(_enabledStorageKey(uid));
  }

  /// Retries cancellation for reminders belonging to every other account.
  Future<void> clearUsersExcept(String? activeUid) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where(
          (key) => key.startsWith(_storagePrefix) && !key.endsWith('.enabled'),
        )
        .toList(growable: false);
    for (final key in keys) {
      final encodedUid = key.substring(_storagePrefix.length);
      String uid;
      try {
        uid = utf8.decode(base64Url.decode(encodedUid));
      } on FormatException {
        continue;
      }
      if (uid != activeUid) await pauseUser(uid);
    }
  }

  /// Keeps reminders aligned with the currently visible public event projection.
  Future<void> reconcile({
    required String uid,
    required Set<String> savedEventIds,
    required List<PublicEvent> publicEvents,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final records = _read(prefs, uid);
    final eventsById = {for (final event in publicEvents) event.id: event};
    final globallyEnabled = prefs.getBool(_enabledStorageKey(uid)) ?? true;
    var platformEnabled = false;
    if (globallyEnabled) {
      try {
        platformEnabled = await _platform.notificationsEnabled();
      } catch (_) {
        // Unknown permission state must never schedule a new alarm.
        platformEnabled = false;
      }
    }
    var changed = false;
    for (final entry in records.entries.toList(growable: false)) {
      final event = eventsById[entry.key];
      var record = entry.value;
      if (record.removePending) {
        try {
          await _platform.cancel(record.notificationId);
          records.remove(entry.key);
          changed = true;
        } catch (_) {
          // Keep explicit removals visible until the native alarm is canceled.
        }
        continue;
      }
      final trigger = event == null || !savedEventIds.contains(entry.key)
          ? null
          : eventReminderAtUtc(event, record.lead, now: now);
      if (trigger == null) {
        final eventStart = event == null ? null : eventStartAtUtc(event);
        final current = now?.toUtc() ?? DateTime.now().toUtc();
        // Keep an already-scheduled native alarm after its lead time begins.
        // A live agenda refresh at the trigger instant must not cancel the
        // alarm before the operating system delivers it. Stale reminders are removed once
        // the event itself has started, or by the existing unavailable,
        // permission, and cancellation paths below.
        if (event != null &&
            savedEventIds.contains(entry.key) &&
            eventStart != null &&
            eventStart.isAfter(current) &&
            platformEnabled &&
            !record.paused &&
            !record.cancelPending) {
          continue;
        }
        try {
          await _platform.cancel(record.notificationId);
          records.remove(entry.key);
          changed = true;
        } catch (_) {
          records[entry.key] = record.copyWith(
            paused: true,
            cancelPending: true,
            removePending: true,
          );
          changed = true;
        }
        continue;
      }
      if (!platformEnabled) {
        try {
          await _platform.cancel(record.notificationId);
          records[entry.key] = record.copyWith(
            paused: true,
            cancelPending: false,
          );
        } catch (_) {
          records[entry.key] = record.copyWith(
            paused: true,
            cancelPending: true,
          );
        }
        changed = true;
        continue;
      }
      if (record.cancelPending) {
        try {
          await _platform.cancel(record.notificationId);
          record = record.copyWith(cancelPending: false);
          records[entry.key] = record;
          changed = true;
        } catch (_) {
          // Do not schedule a replacement until the old alarm is canceled.
          continue;
        }
      }
      final currentEvent = event!;
      final request = _request(
        record.notificationId,
        currentEvent,
        record.lead,
        trigger,
      );
      if (record.paused ||
          trigger != record.triggerAtUtc ||
          request.title != record.title ||
          request.body != record.body) {
        var scheduled = false;
        try {
          scheduled = await _platform.schedule(request);
        } catch (_) {
          scheduled = false;
        }
        if (scheduled) {
          records[entry.key] = _ReminderRecord(
            notificationId: record.notificationId,
            lead: record.lead,
            triggerAtUtc: trigger,
            title: request.title,
            body: request.body,
          );
        } else {
          try {
            await _platform.cancel(record.notificationId);
            records[entry.key] = record.copyWith(
              paused: true,
              cancelPending: false,
            );
          } catch (_) {
            records[entry.key] = record.copyWith(
              paused: true,
              cancelPending: true,
            );
            changed = true;
            continue;
          }
        }
        changed = true;
      }
    }
    if (changed) await _write(prefs, uid, records);
  }

  Map<String, _ReminderRecord> _read(SharedPreferences prefs, String uid) {
    final raw = prefs.getString(_storageKey(uid));
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is Map)
            entry.key as String: _ReminderRecord.fromMap(
              Map<String, dynamic>.from(entry.value as Map),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<bool> _write(
    SharedPreferences prefs,
    String uid,
    Map<String, _ReminderRecord> records,
  ) => prefs.setString(
    _storageKey(uid),
    jsonEncode({
      for (final entry in records.entries) entry.key: entry.value.toMap(),
    }),
  );

  String _storageKey(String uid) =>
      '$_storagePrefix${base64Url.encode(utf8.encode(uid))}';

  int _notificationId(String uid, String eventId, SharedPreferences prefs) {
    final used = <int>{};
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith(_storagePrefix),
    )) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        for (final value in decoded.values) {
          if (value is Map && value['notificationId'] is int) {
            final id = value['notificationId'] as int;
            if (id > 0) used.add(id);
          }
        }
      } catch (_) {
        // A malformed account entry cannot claim a notification ID.
      }
    }
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode('$uid::$eventId')) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    if (hash == 0) hash = 1;
    while (used.contains(hash)) {
      hash = hash == 0x7fffffff ? 1 : hash + 1;
    }
    return hash;
  }
}

EventReminderRequest _request(
  int id,
  PublicEvent event,
  EventReminderLead lead,
  DateTime trigger,
) => EventReminderRequest(
  notificationId: id,
  eventId: event.id,
  title: String.fromCharCodes(event.title.trim().runes.take(100)),
  body: 'Começa ${lead.label.replaceFirst(' antes', '')}.',
  triggerAtUtc: trigger.toUtc(),
);

DateTime? eventStartAtUtc(PublicEvent event) {
  final date = dateInBrasilia(event.eventDate);
  if (date == null) return null;
  final timeMatch = RegExp(
    r'^(\d{1,2}):(\d{2})$',
  ).firstMatch(event.startTime.trim());
  final hasEmbeddedTime = date.hour != 0 || date.minute != 0;
  if (timeMatch == null && !hasEmbeddedTime) return null;
  final hour = timeMatch == null ? date.hour : int.parse(timeMatch.group(1)!);
  final minute = timeMatch == null
      ? date.minute
      : int.parse(timeMatch.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return DateTime.utc(
    date.year,
    date.month,
    date.day,
    hour,
    minute,
  ).add(const Duration(hours: 3));
}

DateTime? eventReminderAtUtc(
  PublicEvent event,
  EventReminderLead lead, {
  DateTime? now,
}) {
  final start = eventStartAtUtc(event);
  if (start == null) return null;
  final trigger = start.subtract(lead.duration);
  final current = now?.toUtc() ?? DateTime.now().toUtc();
  return trigger.isAfter(current) ? trigger : null;
}

class _ReminderRecord {
  const _ReminderRecord({
    required this.notificationId,
    required this.lead,
    required this.triggerAtUtc,
    required this.title,
    required this.body,
    this.cancelPending = false,
    this.paused = false,
    this.removePending = false,
  });

  final int notificationId;
  final EventReminderLead lead;
  final DateTime triggerAtUtc;
  final String title;
  final String body;
  final bool cancelPending;
  final bool paused;
  final bool removePending;

  _ReminderRecord copyWith({
    bool? cancelPending,
    bool? paused,
    bool? removePending,
  }) => _ReminderRecord(
    notificationId: notificationId,
    lead: lead,
    triggerAtUtc: triggerAtUtc,
    title: title,
    body: body,
    cancelPending: cancelPending ?? this.cancelPending,
    paused: paused ?? this.paused,
    removePending: removePending ?? this.removePending,
  );

  Map<String, Object> toMap() => {
    'notificationId': notificationId,
    'leadHours': lead.duration.inHours,
    'triggerAtMillis': triggerAtUtc.millisecondsSinceEpoch,
    'title': title,
    'body': body,
    'cancelPending': cancelPending,
    'paused': paused,
    'removePending': removePending,
  };

  factory _ReminderRecord.fromMap(Map<String, dynamic> map) {
    final id = map['notificationId'];
    final lead = EventReminderLead.fromHours(map['leadHours'] as int? ?? 0);
    final trigger = map['triggerAtMillis'];
    final title = map['title'];
    final body = map['body'];
    final cancelPending = map['cancelPending'] ?? false;
    final paused = map['paused'] ?? false;
    final removePending = map['removePending'] ?? false;
    if (id is! int ||
        id <= 0 ||
        lead == null ||
        trigger is! int ||
        title is! String ||
        body is! String ||
        cancelPending is! bool ||
        paused is! bool ||
        removePending is! bool) {
      throw const FormatException('Invalid event reminder record.');
    }
    return _ReminderRecord(
      notificationId: id,
      lead: lead,
      triggerAtUtc: DateTime.fromMillisecondsSinceEpoch(trigger, isUtc: true),
      title: title,
      body: body,
      cancelPending: cancelPending,
      paused: paused,
      removePending: removePending,
    );
  }
}
