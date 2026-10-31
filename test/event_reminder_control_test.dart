import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tudo_aqui_macacu/features/events/models/public_event.dart';
import 'package:tudo_aqui_macacu/features/events/services/event_reminder_service.dart';
import 'package:tudo_aqui_macacu/features/events/widgets/event_reminder_control.dart';

class _Platform implements EventReminderPlatform {
  int permissionRequests = 0;
  final scheduled = <int, EventReminderRequest>{};

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Future<bool> openNotificationSettings() async => true;

  @override
  Future<bool> schedule(EventReminderRequest request) async {
    scheduled[request.notificationId] = request;
    return true;
  }

  @override
  Future<void> cancel(int notificationId) async {
    scheduled.remove(notificationId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'asks notification permission only after the user chooses a reminder',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final platform = _Platform();
      final service = EventReminderService(platform: platform, isAndroid: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventReminderControl(
              uid: 'resident-a',
              event: const PublicEvent(
                id: 'community-fair',
                title: 'Feira da Cidade',
                eventDate: '15/11/2030',
                startTime: '18:30',
              ),
              service: service,
              now: DateTime.utc(2030, 11, 14, 19),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(platform.permissionRequests, 0);
      await tester.tap(find.byKey(const Key('event-reminder-enable')));
      await tester.pumpAndSettle();
      expect(find.text('1 hora antes'), findsOneWidget);
      await tester.tap(find.text('1 hora antes'));
      await tester.pumpAndSettle();

      expect(platform.permissionRequests, 1);
      expect(find.text('Lembrete: 1 hora antes'), findsOneWidget);
      expect(platform.scheduled, hasLength(1));
    },
  );
}
