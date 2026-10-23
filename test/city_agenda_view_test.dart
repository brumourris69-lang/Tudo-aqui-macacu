import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/features/events/models/public_event.dart';
import 'package:tudo_aqui_macacu/features/events/pages/event_detail_page.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

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

class _EventStreams {
  final controllers = <StreamController<PublicContentSnapshot>>[];

  Stream<PublicContentSnapshot> create() {
    final controller = StreamController<PublicContentSnapshot>();
    controllers.add(controller);
    return controller.stream;
  }
}

Widget _app(
  _EventStreams streams, {
  Future<PublicEvent?> Function(String id)? resolveEvent,
}) => MaterialApp(
  home: CityAgendaView(
    eventsStreamFactory: streams.create,
    resolveEvent: resolveEvent,
  ),
);

String _localDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void _expectTextOrder(WidgetTester tester, List<String> expected) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .toList();
  var previousIndex = -1;
  for (final value in expected) {
    final index = texts.indexOf(value);
    expect(
      index,
      greaterThan(previousIndex),
      reason: 'Expected $value in order',
    );
    previousIndex = index;
  }
}

void main() {
  testWidgets('agenda stream failure offers retry and recovers', (
    tester,
  ) async {
    final streams = _EventStreams();
    await tester.pumpWidget(_app(streams));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    streams.controllers.single.addError(StateError('offline'));
    await tester.pump();
    expect(find.text('Não foi possível carregar a agenda.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(streams.controllers, hasLength(2));
    streams.controllers[1].add(_snapshot(const []));
    await tester.pump();
    expect(
      find.text(
        'Nenhum evento publicado. A agenda só exibe informações reais cadastradas pelo administrador.',
      ),
      findsOneWidget,
    );
    expect(find.text('Não foi possível carregar a agenda.'), findsNothing);
  });

  testWidgets('agenda card opens secure event detail with original ID', (
    tester,
  ) async {
    final streams = _EventStreams();
    String? resolvedId;
    await tester.pumpWidget(
      _app(
        streams,
        resolveEvent: (id) async {
          resolvedId = id;
          return PublicEvent(id: id, title: 'Detalhe público');
        },
      ),
    );
    streams.controllers.single.add(
      _snapshot([
        (
          id: 'event-real-document-id',
          data: {
            'title': 'Festa comunitária',
            'eventDate': DateTime.now()
                .add(const Duration(days: 3))
                .toIso8601String(),
            'published': true,
            'active': true,
          },
        ),
      ]),
    );
    await tester.pump();

    await tester.tap(find.text('Festa comunitária'));
    await tester.pumpAndSettle();
    expect(resolvedId, 'event-real-document-id');
    expect(find.byType(EventDetailPage), findsOneWidget);
    expect(find.text('Detalhe público'), findsOneWidget);
  });

  testWidgets('agenda link action keeps the local safe-link behavior', (
    tester,
  ) async {
    final streams = _EventStreams();
    await tester.pumpWidget(_app(streams));
    streams.controllers.single.add(
      _snapshot([
        (
          id: 'event-with-link',
          data: {
            'title': 'Evento com link',
            'eventDate': DateTime.now()
                .add(const Duration(days: 3))
                .toIso8601String(),
            'published': true,
            'active': true,
            'link': 'https://example.invalid/evento',
          },
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Abrir link'), findsOneWidget);
    await tester.tap(find.text('Abrir link'));
    await tester.pump();
    if (LocalSearchEnvironment.enabled) {
      expect(
        find.text('Links externos indisponíveis no ambiente local.'),
        findsOneWidget,
      );
    }
    expect(find.byType(EventDetailPage), findsNothing);
  }, skip: !LocalSearchEnvironment.enabled);

  testWidgets('upcoming group excludes past and invalid event dates', (
    tester,
  ) async {
    final streams = _EventStreams();
    final now = DateTime.now();
    await tester.pumpWidget(_app(streams));
    streams.controllers.single.add(
      _snapshot([
        (
          id: 'future-event',
          data: {
            'title': 'Evento futuro válido',
            'eventDate': now.add(const Duration(days: 3)).toIso8601String(),
            'published': true,
            'active': true,
          },
        ),
        (
          id: 'past-event',
          data: {
            'title': 'Evento passado',
            'eventDate': now
                .subtract(const Duration(days: 3))
                .toIso8601String(),
            'published': true,
            'active': true,
          },
        ),
        (
          id: 'invalid-event',
          data: {
            'title': 'Evento com data inválida',
            'eventDate': 'data não reconhecida',
            'published': true,
            'active': true,
          },
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Evento futuro válido'), findsOneWidget);
    expect(find.text('Evento passado'), findsNothing);
    expect(find.text('Evento com data inválida'), findsNothing);
  });

  testWidgets('offset dates are grouped by their local calendar day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final streams = _EventStreams();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final future = today.add(const Duration(days: 8));
    await tester.pumpWidget(_app(streams));
    streams.controllers.single.add(
      _snapshot([
        (
          id: 'offset-today',
          data: {
            'title': 'Evento hoje com offset',
            'eventDate': '${_localDate(today)}T23:30:00-03:00',
            'published': true,
            'active': true,
          },
        ),
        (
          id: 'offset-tomorrow',
          data: {
            'title': 'Evento amanhã com offset',
            'eventDate': '${_localDate(tomorrow)}T18:00:00-03:00',
            'published': true,
            'active': true,
          },
        ),
        (
          id: 'offset-future',
          data: {
            'title': 'Evento próximo com offset',
            'eventDate': '${_localDate(future)}T16:00:00-03:00',
            'published': true,
            'active': true,
          },
        ),
      ]),
    );
    await tester.pump();

    _expectTextOrder(tester, const [
      'Hoje',
      'Evento hoje com offset',
      'Amanhã',
      'Evento amanhã com offset',
      'Próximos',
      'Evento próximo com offset',
    ]);
  });

  testWidgets('UTC timestamps that cross midnight are grouped locally', (
    tester,
  ) async {
    final streams = _EventStreams();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lateToday = DateTime(today.year, today.month, today.day, 23, 30);
    await tester.pumpWidget(_app(streams));
    streams.controllers.single.add(
      _snapshot([
        (
          id: 'utc-local-rollover',
          data: {
            'title': 'Evento perto da meia-noite local',
            'eventDate': lateToday.toUtc().toIso8601String(),
            'published': true,
            'active': true,
          },
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text('Evento perto da meia-noite local'), findsOneWidget);
    expect(find.text('Amanhã'), findsNothing);
  });

  testWidgets('impossible ISO calendar dates are excluded', (tester) async {
    final streams = _EventStreams();
    await tester.pumpWidget(_app(streams));
    streams.controllers.single.add(
      _snapshot([
        (
          id: 'impossible-date',
          data: {
            'title': 'Evento com data impossível',
            'eventDate': '2099-02-30T10:00:00-03:00',
            'published': true,
            'active': true,
          },
        ),
        (
          id: 'impossible-legacy-date',
          data: {
            'title': 'Evento com data legada impossível',
            'eventDate': '31/02/2099',
            'published': true,
            'active': true,
          },
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Nenhum evento futuro com data válida.'), findsOneWidget);
    expect(find.text('Evento com data impossível'), findsNothing);
    expect(find.text('Evento com data legada impossível'), findsNothing);
  });

  testWidgets('valid legacy date formats remain accepted', (tester) async {
    final streams = _EventStreams();
    final future = DateTime.now().add(const Duration(days: 8));
    await tester.pumpWidget(_app(streams));
    streams.controllers.single.add(
      _snapshot([
        (
          id: 'legacy-date',
          data: {
            'title': 'Evento com data legada válida',
            'eventDate':
                '${future.day.toString().padLeft(2, '0')}/'
                '${future.month.toString().padLeft(2, '0')}/'
                '${future.year}',
            'published': true,
            'active': true,
          },
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Evento com data legada válida'), findsOneWidget);
    expect(find.text('Próximos'), findsOneWidget);
  });

  testWidgets('agenda with only invalid dates shows a clear empty state', (
    tester,
  ) async {
    final streams = _EventStreams();
    await tester.pumpWidget(_app(streams));
    streams.controllers.single.add(
      _snapshot([
        (
          id: 'invalid-event',
          data: {
            'title': 'Evento sem data válida',
            'eventDate': 'data não reconhecida',
            'published': true,
            'active': true,
          },
        ),
      ]),
    );
    await tester.pump();
    expect(find.text('Nenhum evento futuro com data válida.'), findsOneWidget);
    expect(find.text('Evento sem data válida'), findsNothing);
  });
}
