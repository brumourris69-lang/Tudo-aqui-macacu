import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/features/events/models/public_event.dart';
import 'package:tudo_aqui_macacu/features/events/pages/event_reminder_settings_view.dart';
import 'package:tudo_aqui_macacu/features/events/services/event_reminder_service.dart';

class _Platform implements EventReminderPlatform {
  final scheduled = <int, EventReminderRequest>{};
  bool permissionEnabled = true;
  bool failCancel = false;
  bool settingsOpened = false;

  @override
  Future<bool> requestPermission() async => permissionEnabled;

  @override
  Future<bool> notificationsEnabled() async => permissionEnabled;

  @override
  Future<bool> openNotificationSettings() async {
    settingsOpened = true;
    return true;
  }

  @override
  Future<bool> schedule(EventReminderRequest request) async {
    if (!permissionEnabled) return false;
    scheduled[request.notificationId] = request;
    return true;
  }

  @override
  Future<void> cancel(int notificationId) async {
    if (failCancel) throw StateError('platform cancellation unavailable');
    scheduled.remove(notificationId);
  }
}

const _event = PublicEvent(
  id: 'feira',
  title: 'Feira de Macacu',
  eventDate: '15/11/2030',
  startTime: '18:30',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Platform platform;
  late EventReminderService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    platform = _Platform();
    service = EventReminderService(platform: platform, isAndroid: true);
    await service.activate(
      uid: 'resident-a',
      event: _event,
      lead: EventReminderLead.oneHour,
      now: DateTime.utc(2030, 11, 14, 19),
    );
  });

  Widget buildSettings({
    List<PublicEvent> events = const [_event],
    Stream<String?> Function()? accountUidStreamFactory,
  }) => MaterialApp(
    theme: AppTheme.light,
    home: EventReminderSettingsView(
      uid: 'resident-a',
      savedEventIds: const {'feira'},
      eventsStreamFactory: () => Stream.value(events),
      accountUidStreamFactory: accountUidStreamFactory,
      service: service,
    ),
  );

  testWidgets(
    'global toggle pauses and restores reminders without deleting them',
    (tester) async {
      await tester.pumpWidget(buildSettings());
      await tester.pumpAndSettle();

      expect(find.text('Feira de Macacu'), findsOneWidget);
      expect(find.textContaining('Aviso previsto para'), findsOneWidget);
      expect(find.textContaining('(Brasília)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('event-reminders-global-toggle')));
      await tester.pumpAndSettle();

      expect(await service.remindersEnabled('resident-a'), isFalse);
      expect(await service.reminderSettings('resident-a'), hasLength(1));
      expect(platform.scheduled, isEmpty);
      expect(find.textContaining('Pausado'), findsOneWidget);

      await tester.tap(find.byKey(const Key('event-reminders-global-toggle')));
      await tester.pumpAndSettle();

      expect(await service.remindersEnabled('resident-a'), isTrue);
      expect(await service.reminderSettings('resident-a'), hasLength(1));
      expect(platform.scheduled, hasLength(1));
    },
  );

  testWidgets(
    'explains disabled notification permission and opens system settings',
    (tester) async {
      platform.permissionEnabled = false;
      await tester.pumpWidget(buildSettings());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('event-reminder-permission-warning')),
        findsOneWidget,
      );
      expect(find.text('Abrir configurações'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('event-reminder-open-system-settings')),
      );
      await tester.pumpAndSettle();
      expect(platform.settingsOpened, isTrue);
    },
  );

  testWidgets(
    'keeps an unavailable event cancellation visible until confirmed',
    (tester) async {
      platform.failCancel = true;
      await tester.pumpWidget(buildSettings(events: const []));
      await tester.pumpAndSettle();

      expect(
        (await service.reminderSettings('resident-a')).single.removalPending,
        isTrue,
      );
      expect(find.textContaining('Cancelamento pendente'), findsOneWidget);
      expect(
        find.textContaining('removido assim que o aparelho confirmar'),
        findsOneWidget,
      );
      expect(await service.reminderSettings('resident-a'), hasLength(1));

      platform.failCancel = false;
      await tester.tap(find.byTooltip('Cancelar lembrete'));
      await tester.pumpAndSettle();
      expect(await service.reminderSettings('resident-a'), isEmpty);
    },
  );

  testWidgets('locks settings when the authenticated account changes', (
    tester,
  ) async {
    final accountController = StreamController<String?>();
    await tester.pumpWidget(
      buildSettings(accountUidStreamFactory: () => accountController.stream),
    );
    await tester.pumpAndSettle();

    accountController.add(null);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('Sua sessão mudou'), findsOneWidget);
    expect(
      find.byKey(const Key('event-reminders-global-toggle')),
      findsNothing,
    );
    expect(platform.scheduled, isEmpty);
    expect(await service.reminderSettings('resident-a'), hasLength(1));
    await accountController.close();
  });
}
