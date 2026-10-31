import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/features/events/models/public_event.dart';
import 'package:tudo_aqui_macacu/features/events/pages/my_agenda_view.dart';

// ignore: subtype_of_sealed_class
class _DocumentReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PublicContentDocument _event(String id, Map<String, dynamic> data) =>
    PublicContentDocument(id, data, _DocumentReference());

PublicContentSnapshot _snapshot(
  List<({String id, Map<String, dynamic> data})> events,
) => PublicContentSnapshot([
  for (final event in events) _event(event.id, event.data),
]);

void main() {
  testWidgets('agenda shows only saved published events and removes one', (
    tester,
  ) async {
    PublicEvent? removed;
    await tester.pumpWidget(
      MaterialApp(
        home: MyAgendaView(
          savedEventIds: const {'event-1', 'hidden-event'},
          eventsStreamFactory: () => Stream.value(
            _snapshot([
              (
                id: 'event-1',
                data: {
                  'title': 'Festival de Teste',
                  'eventDate': '15/11/2030',
                  'startTime': '18:30',
                  'category': 'Cultura',
                  'published': true,
                  'active': true,
                },
              ),
              (
                id: 'hidden-event',
                data: {
                  'title': 'Rascunho oculto',
                  'eventDate': '16/11/2030',
                  'published': false,
                  'active': true,
                },
              ),
            ]),
          ),
          onRemove: (event) async {
            removed = event;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Festival de Teste'), findsOneWidget);
    expect(find.text('18:30'), findsOneWidget);
    expect(find.text('Cultura'), findsOneWidget);
    expect(find.text('Rascunho oculto'), findsNothing);
    await tester.tap(find.text('Remover'));
    expect(removed?.id, 'event-1');
  });

  testWidgets('ended events stay saved and are clearly identified', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyAgendaView(
          savedEventIds: const {'old-event'},
          eventsStreamFactory: () => Stream.value(
            _snapshot([
              (
                id: 'old-event',
                data: {
                  'title': 'Evento encerrado',
                  'eventDate': '01/01/2020',
                  'published': true,
                  'active': true,
                },
              ),
            ]),
          ),
          onRemove: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Evento encerrado'), findsOneWidget);
    expect(find.text('Encerrado'), findsOneWidget);
  });

  testWidgets('agenda offers retry after the public stream fails', (
    tester,
  ) async {
    final streams = <StreamController<PublicContentSnapshot>>[];
    Stream<PublicContentSnapshot> createStream() {
      final controller = StreamController<PublicContentSnapshot>();
      streams.add(controller);
      return controller.stream;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MyAgendaView(
          savedEventIds: const {'event-1'},
          eventsStreamFactory: createStream,
          onRemove: (_) async => true,
        ),
      ),
    );
    streams.single.addError(StateError('internal detail'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar sua agenda.'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(streams, hasLength(2));
    streams.last.add(
      _snapshot([
        (
          id: 'event-1',
          data: {
            'title': 'Evento recuperado',
            'eventDate': '20/12/2030',
            'published': true,
            'active': true,
          },
        ),
      ]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Evento recuperado'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
