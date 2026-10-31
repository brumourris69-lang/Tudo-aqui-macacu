import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/events/models/public_event.dart';
import 'package:tudo_aqui_macacu/features/events/pages/event_detail_page.dart';

void main() {
  testWidgets('event detail shows a retryable error then public content', (
    tester,
  ) async {
    final pending = Completer<PublicEvent?>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EventDetailPage(
          eventId: 'event-local-1',
          resolveEvent: (_) {
            calls++;
            if (calls == 1) return pending.future;
            return Future.value(
              const PublicEvent(
                id: 'event-local-1',
                title: 'Evento de Teste',
                description: 'Conteúdo público completo.',
              ),
            );
          },
        ),
      ),
    );
    pending.completeError(StateError('detalhe interno não exibido'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar este evento.'), findsOneWidget);
    expect(find.textContaining('detalhe interno'), findsNothing);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Evento de Teste'), findsOneWidget);
    expect(find.text('Conteúdo público completo.'), findsOneWidget);
  });

  testWidgets('event detail displays the public schedule and safe actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EventDetailPage(
          eventId: 'event-local-2',
          resolveEvent: (_) async => const PublicEvent(
            id: 'event-local-2',
            title: 'Feira fictícia',
            category: 'Cultura',
            eventDate: '31/12/2030',
            endDate: '02/01/2031',
            startTime: '19:30',
            endTime: '22:00',
            location: 'Praça de teste',
            address: 'Rua de teste, 10',
            organizer: 'Organização fictícia',
            maps: 'https://maps.example.invalid/evento',
            registrationUrl: 'https://events.example.invalid/inscricao',
            contactUrl: 'https://events.example.invalid/contato',
            description: 'Programação cadastrada pelo administrador.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final value in [
      'Feira fictícia',
      'Cultura',
      '31/12/2030 até 02/01/2031 · 19:30 · até 22:00',
      'Praça de teste',
      'Rua de teste, 10',
      'Organização fictícia',
      'Programação cadastrada pelo administrador.',
    ]) {
      expect(find.text(value), findsOneWidget, reason: value);
    }
    expect(find.text('Ver localização'), findsOneWidget);
    expect(find.text('Inscreva-se'), findsOneWidget);
    expect(find.text('Falar com organizador'), findsOneWidget);
  });

  testWidgets(
    'public event detail has a share action with public fields only',
    (tester) async {
      String? shared;
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailPage(
            eventId: 'public-event',
            onShare: (content) async => shared = content.message,
            resolveEvent: (_) async => const PublicEvent(
              id: 'public-event',
              title: 'Festival local',
              description: 'Música e cultura.',
              organizer: 'Informação pública que não deve ser incluída',
              contactUrl: 'https://private.invalid/contact',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Compartilhar evento'));
      await tester.pump();
      expect(shared, contains('Festival local'));
      expect(shared, contains('Música e cultura.'));
      expect(shared, isNot(contains('private.invalid')));
      expect(shared, contains('Encontre no app Tudo Aqui Macacu.'));
    },
  );

  testWidgets('unavailable event has no public share action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EventDetailPage(
          eventId: 'unavailable-event',
          resolveEvent: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Este evento não está mais disponível.'), findsOneWidget);
    expect(find.byTooltip('Compartilhar evento'), findsNothing);
  });

  testWidgets('event detail adds and removes an event from personal agenda', (
    tester,
  ) async {
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EventDetailPage(
          eventId: 'agenda-event',
          resolveEvent: (_) async => const PublicEvent(
            id: 'agenda-event',
            title: 'Feira da Comunidade',
          ),
          onToggleAgenda: (_) async {
            saved = !saved;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('event-agenda-toggle')));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(find.text('Remover da Minha Agenda'), findsOneWidget);

    await tester.tap(find.byKey(const Key('event-agenda-toggle')));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(find.text('Adicionar à Minha Agenda'), findsOneWidget);
  });
}
