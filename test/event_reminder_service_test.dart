import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tudo_aqui_macacu/features/events/models/public_event.dart';
import 'package:tudo_aqui_macacu/features/events/services/event_reminder_service.dart';

class _ReminderPlatform implements EventReminderPlatform {
  final scheduled = <int, EventReminderRequest>{};
  final cancelled = <int>[];
  bool permissionGranted = true;
  bool systemNotificationsEnabled = true;
  bool settingsOpened = false;
  bool failCancel = false;
  bool throwAfterScheduling = false;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<bool> notificationsEnabled() async => systemNotificationsEnabled;

  @override
  Future<bool> openNotificationSettings() async {
    settingsOpened = true;
    return true;
  }

  @override
  Future<bool> schedule(EventReminderRequest request) async {
    scheduled[request.notificationId] = request;
    if (throwAfterScheduling) throw StateError('simulated platform failure');
    return true;
  }

  @override
  Future<void> cancel(int notificationId) async {
    cancelled.add(notificationId);
    if (failCancel) throw StateError('simulated cancellation failure');
    scheduled.remove(notificationId);
  }
}

PublicEvent _event({
  String id = 'festival-1',
  String date = '15/11/2030',
  String time = '18:30',
  String title = 'Festival da Praça',
}) => PublicEvent(id: id, title: title, eventDate: date, startTime: time);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'calculates lead times from Brasília wall time, not device timezone',
    () {
      final now = DateTime.utc(2030, 11, 14, 19);

      expect(
        eventReminderAtUtc(_event(), EventReminderLead.oneHour, now: now),
        DateTime.utc(2030, 11, 15, 20, 30),
      );
      expect(
        eventReminderAtUtc(_event(), EventReminderLead.oneDay, now: now),
        DateTime.utc(2030, 11, 14, 21, 30),
      );
    },
  );

  test('rejects missing, malformed, and already-past start times', () {
    final now = DateTime.utc(2030, 11, 15, 22);
    expect(
      eventReminderAtUtc(_event(time: ''), EventReminderLead.oneHour, now: now),
      isNull,
    );
    expect(
      eventReminderAtUtc(
        _event(time: '25:90'),
        EventReminderLead.oneHour,
        now: now,
      ),
      isNull,
    );
    expect(
      eventReminderAtUtc(_event(), EventReminderLead.oneHour, now: now),
      isNull,
    );
  });

  group('EventReminderService', () {
    late _ReminderPlatform platform;
    late EventReminderService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      platform = _ReminderPlatform();
      service = EventReminderService(platform: platform, isAndroid: true);
    });

    test(
      'asks permission on user action and replaces the same event alarm',
      () async {
        final now = DateTime.utc(2030, 11, 14, 19);
        final first = await service.activate(
          uid: 'user-a',
          event: _event(),
          lead: EventReminderLead.oneHour,
          now: now,
        );
        final second = await service.activate(
          uid: 'user-a',
          event: _event(),
          lead: EventReminderLead.oneDay,
          now: now,
        );

        expect(first, EventReminderResult.scheduled);
        expect(second, EventReminderResult.scheduled);
        expect(platform.scheduled, hasLength(1));
        expect(
          platform.scheduled.values.single.triggerAtUtc,
          DateTime.utc(2030, 11, 14, 21, 30),
        );
        expect(
          await service.leadFor('user-a', 'festival-1'),
          EventReminderLead.oneDay,
        );
      },
    );

    test(
      'keeps the chosen reminder paused when Android permission is denied',
      () async {
        platform.permissionGranted = false;

        final result = await service.activate(
          uid: 'user-a',
          event: _event(),
          lead: EventReminderLead.oneHour,
          now: DateTime.utc(2030, 11, 14, 19),
        );

        expect(result, EventReminderResult.permissionDenied);
        expect(platform.scheduled, isEmpty);
        expect(
          await service.leadFor('user-a', 'festival-1'),
          EventReminderLead.oneHour,
        );
        expect(
          (await service.reminderSettings('user-a')).single.paused,
          isTrue,
        );
      },
    );

    test(
      'cancels a partially scheduled alarm after platform failure',
      () async {
        platform.throwAfterScheduling = true;
        final result = await service.activate(
          uid: 'user-a',
          event: _event(),
          lead: EventReminderLead.oneHour,
          now: DateTime.utc(2030, 11, 14, 19),
        );

        expect(result, EventReminderResult.failed);
        expect(platform.scheduled, isEmpty);
        expect(await service.leadFor('user-a', 'festival-1'), isNull);
      },
    );

    test(
      'retries failed native cancellation without treating it as active',
      () async {
        platform.throwAfterScheduling = true;
        platform.failCancel = true;
        final result = await service.activate(
          uid: 'user-a',
          event: _event(),
          lead: EventReminderLead.oneHour,
          now: DateTime.utc(2030, 11, 14, 19),
        );
        expect(result, EventReminderResult.failed);
        expect(await service.hasReminders('user-a'), isTrue);

        platform.throwAfterScheduling = false;
        platform.failCancel = false;
        await service.reconcile(
          uid: 'user-a',
          savedEventIds: const {'festival-1'},
          publicEvents: [_event()],
          now: DateTime.utc(2030, 11, 14, 19),
        );

        expect(await service.hasReminders('user-a'), isTrue);
        expect(platform.scheduled, hasLength(1));
        expect(
          (await service.reminderSettings('user-a')).single.paused,
          isFalse,
        );
      },
    );

    test(
      'cancels reminders for removed or unavailable agenda events',
      () async {
        final now = DateTime.utc(2030, 11, 14, 19);
        await service.activate(
          uid: 'user-a',
          event: _event(),
          lead: EventReminderLead.oneHour,
          now: now,
        );

        await service.reconcile(
          uid: 'user-a',
          savedEventIds: const {'festival-1'},
          publicEvents: const [],
          now: now,
        );

        expect(platform.scheduled, isEmpty);
        expect(await service.leadFor('user-a', 'festival-1'), isNull);
      },
    );

    test(
      'moves a pending reminder when the public event start time changes',
      () async {
        final now = DateTime.utc(2030, 11, 14, 19);
        await service.activate(
          uid: 'user-a',
          event: _event(),
          lead: EventReminderLead.oneHour,
          now: now,
        );
        final notificationId = platform.scheduled.keys.single;

        await service.reconcile(
          uid: 'user-a',
          savedEventIds: const {'festival-1'},
          publicEvents: [_event(time: '20:30', title: 'Festival remarcado')],
          now: now,
        );

        expect(platform.scheduled, hasLength(1));
        expect(platform.scheduled.keys.single, notificationId);
        expect(
          platform.scheduled.values.single.triggerAtUtc,
          DateTime.utc(2030, 11, 15, 22, 30),
        );
        expect(platform.scheduled.values.single.title, 'Festival remarcado');
      },
    );

    test(
      'does not cancel a due native alarm before the event starts',
      () async {
        final scheduledAt = DateTime.utc(2030, 11, 14, 19);
        await service.activate(
          uid: 'user-a',
          event: _event(),
          lead: EventReminderLead.oneHour,
          now: scheduledAt,
        );
        final notificationId = platform.scheduled.keys.single;

        await service.reconcile(
          uid: 'user-a',
          savedEventIds: const {'festival-1'},
          publicEvents: [_event()],
          now: DateTime.utc(2030, 11, 15, 20, 31),
        );

        expect(platform.scheduled, hasLength(1));
        expect(platform.scheduled.containsKey(notificationId), isTrue);
        expect(platform.cancelled, isEmpty);
        expect(
          await service.leadFor('user-a', 'festival-1'),
          EventReminderLead.oneHour,
        );

        await service.reconcile(
          uid: 'user-a',
          savedEventIds: const {'festival-1'},
          publicEvents: [_event()],
          now: DateTime.utc(2030, 11, 15, 21, 31),
        );

        expect(platform.scheduled, isEmpty);
        expect(await service.leadFor('user-a', 'festival-1'), isNull);
      },
    );

    test('clears only the signed-out account notification alarms', () async {
      final now = DateTime.utc(2030, 11, 14, 19);
      await service.activate(
        uid: 'user-a',
        event: _event(),
        lead: EventReminderLead.oneHour,
        now: now,
      );
      await service.activate(
        uid: 'user-b',
        event: _event(id: 'another-event'),
        lead: EventReminderLead.oneHour,
        now: now,
      );

      await service.clearUser('user-a');

      expect(platform.scheduled, hasLength(1));
      expect(await service.leadFor('user-a', 'festival-1'), isNull);
      expect(
        await service.leadFor('user-b', 'another-event'),
        EventReminderLead.oneHour,
      );
    });

    test(
      'global disable pauses alarms but preserves agenda reminder choices',
      () async {
        final now = DateTime.utc(2030, 11, 14, 19);
        await service.activate(
          uid: 'user-a',
          event: _event(),
          lead: EventReminderLead.oneHour,
          now: now,
        );

        await service.setRemindersEnabled('user-a', false);

        expect(await service.remindersEnabled('user-a'), isFalse);
        expect(platform.scheduled, isEmpty);
        expect(await service.reminderSettings('user-a'), hasLength(1));
        expect(
          (await service.reminderSettings('user-a')).single.paused,
          isTrue,
        );
        expect(
          await service.leadFor('user-a', 'festival-1'),
          EventReminderLead.oneHour,
        );

        await service.setRemindersEnabled('user-a', true);
        await service.reconcile(
          uid: 'user-a',
          savedEventIds: const {'festival-1'},
          publicEvents: [_event()],
          now: now,
        );

        expect(await service.remindersEnabled('user-a'), isTrue);
        expect(platform.scheduled, hasLength(1));
        expect(
          (await service.reminderSettings('user-a')).single.paused,
          isFalse,
        );
      },
    );

    test('does not schedule when Android notifications are disabled', () async {
      final now = DateTime.utc(2030, 11, 14, 19);
      await service.activate(
        uid: 'user-a',
        event: _event(),
        lead: EventReminderLead.oneHour,
        now: now,
      );
      platform.systemNotificationsEnabled = false;

      await service.reconcile(
        uid: 'user-a',
        savedEventIds: const {'festival-1'},
        publicEvents: [_event()],
        now: now,
      );

      expect(platform.scheduled, isEmpty);
      expect((await service.reminderSettings('user-a')).single.paused, isTrue);
    });

    test('keeps settings account-scoped and pauses alarms at logout', () async {
      final now = DateTime.utc(2030, 11, 14, 19);
      await service.activate(
        uid: 'user-a',
        event: _event(),
        lead: EventReminderLead.oneHour,
        now: now,
      );
      await service.activate(
        uid: 'user-b',
        event: _event(id: 'another-event'),
        lead: EventReminderLead.oneHour,
        now: now,
      );

      await service.setRemindersEnabled('user-a', false);
      await service.pauseUser('user-a');

      expect(await service.remindersEnabled('user-a'), isFalse);
      expect(await service.remindersEnabled('user-b'), isTrue);
      expect(await service.reminderSettings('user-a'), hasLength(1));
      expect((await service.reminderSettings('user-a')).single.paused, isTrue);
      expect(await service.reminderSettings('user-b'), hasLength(1));
      expect(platform.scheduled, hasLength(1));
    });

    test('retains failed cancellations so they can be retried', () async {
      final now = DateTime.utc(2030, 11, 14, 19);
      await service.activate(
        uid: 'user-a',
        event: _event(),
        lead: EventReminderLead.oneHour,
        now: now,
      );
      platform.failCancel = true;

      await service.clearUsersExcept('user-b');

      expect(await service.hasReminders('user-a'), isTrue);
      expect(platform.scheduled, hasLength(1));

      platform.failCancel = false;
      await service.clearUsersExcept('user-b');

      expect(await service.hasReminders('user-a'), isTrue);
      expect(platform.scheduled, isEmpty);
      expect((await service.reminderSettings('user-a')).single.paused, isTrue);
    });

    test(
      'notification ids do not collide across account event records',
      () async {
        final now = DateTime.utc(2030, 11, 14, 19);
        await service.activate(
          uid: 'user-a',
          event: _event(),
          lead: EventReminderLead.oneHour,
          now: now,
        );
        await service.activate(
          uid: 'user-b',
          event: _event(),
          lead: EventReminderLead.oneHour,
          now: now,
        );

        expect(platform.scheduled, hasLength(2));
        expect(platform.scheduled.keys.toSet(), hasLength(2));
      },
    );
  });
}
