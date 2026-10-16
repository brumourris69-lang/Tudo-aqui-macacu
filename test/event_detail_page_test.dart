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
}
