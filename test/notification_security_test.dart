import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tudo_aqui_macacu/features/notifications/notification_repository.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test('public content has no recipient; private content has only UID', () {
    final public = notificationContent(
      title: ' Aviso ',
      description: 'Mensagem',
      link: 'https://example.invalid',
      timestamp: 1,
    );
    expect(public['targetEmail'], '');
    expect(public.containsKey('targetUid'), isFalse);
    final private = notificationContent(
      title: 'Privada',
      description: 'Mensagem',
      link: '',
      timestamp: 1,
      targetUid: 'owner',
    );
    expect(private['targetUid'], 'owner');
    expect(private.containsKey('targetEmail'), isFalse);
  });
  test('merges authorized streams and cancels both subscriptions', () async {
    final public = StreamController<List<Map<String, dynamic>>>();
    final private = StreamController<List<Map<String, dynamic>>>();
    final values = <List<Map<String, dynamic>>>[];
    final subscription = mergeNotificationStreams(
      public.stream,
      private.stream,
    ).listen(values.add);
    public.add([
      {'title': 'Pública'},
    ]);
    private.add([
      {'title': 'Privada'},
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(values.single.map((v) => v['title']), ['Pública', 'Privada']);
    await subscription.cancel();
    expect(public.hasListener, isFalse);
    expect(private.hasListener, isFalse);
    await public.close();
    await private.close();
  });
  testWidgets(
    'existing interface shows authorized public/private messages and filters expired content',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsView(
            notifications: Stream.value([
              {
                'title': 'Comunicado público',
                'description': 'Mensagem pública',
              },
              {
                'title': 'Mensagem particular',
                'description': 'Conteúdo do destinatário',
              },
              {
                'title': 'Oculta',
                'expiresAt': Timestamp.fromMillisecondsSinceEpoch(1),
              },
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Comunicado público'), findsOneWidget);
      expect(find.text('Mensagem particular'), findsOneWidget);
      expect(find.text('Oculta'), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(2));
    },
  );
  testWidgets('empty state and connection failure remain explicit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: NotificationsView(notifications: Stream.value([]))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Você está em dia'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsView(
          notifications: Stream.error(StateError('denied')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Não foi possível carregar as notificações.'),
      findsOneWidget,
    );
  });
}
