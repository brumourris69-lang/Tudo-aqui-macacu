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
  DateTime Function()? clock,
  Future<PublicEvent?> Function(String id)? resolveEvent,
  Set<String> savedEventIds = const {},
  Future<bool> Function(PublicEvent event)? onToggleAgenda,
  VoidCallback? onOpenMyAgenda,
}) => MaterialApp(
  home: CityAgendaView(
    eventsStreamFactory: streams.create,
    clock: clock,
    resolveEvent: resolveEvent,
    savedEventIds: savedEventIds,
    onToggleAgenda: onToggleAgenda,
    onOpenMyAgenda: onOpenMyAgenda,
  ),
);

String _localDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void _expectTextOrder(WidgetTester tester, List<String> expected) {
  final topPositions = expected
      .map((value) => tester.getTopLeft(find.text(value).first).dy)
      .toList();
  expect(topPositions, orderedEquals([...topPositions]..sort()));
}

void main() {
  testWidgets('event cards save to agenda and open its dedicated page', (
    tester,
  ) async {
    final streams = _EventStreams();
    PublicEvent? selected;
    var agendaOpened = false;
    await tester.pumpWidget(
      _app(
        streams,
        onToggleAgenda: (event) async {
          selected = event;
          return true;
        },
        onOpenMyAgenda: () => agendaOpened = true,
      ),
    );
    streams.controllers.single.add(
      _snapshot([
        (
          id: 'festival-agenda-test',
          data: {
            'title': 'Festival de Teste',
            'eventDate': '31/12/2030',
            'published': true,
            'active': true,
          },
        ),
      ]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Adicionar evento à Minha Agenda'));
    await tester.pump();
    expect(selected?.id, 'festival-agenda-test');
    expect(selected?.title, 'Festival de Teste');

    await tester.tap(find.byTooltip('Minha Agenda'));
    expect(agendaOpened, isTrue);
  });

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

  testWidgets(
    'calendar marks and lists multi-day public events for a selected day',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final streams = _EventStreams();
      String? resolvedId;
      final selected = DateTime.now().add(const Duration(days: 3));
      final day = DateTime(selected.year, selected.month, selected.day);
      final start = day.subtract(const Duration(days: 1));
      final end = day.add(const Duration(days: 1));
      await tester.pumpWidget(
        _app(
          streams,
          resolveEvent: (id) async {
            resolvedId = id;
            return PublicEvent(id: id, title: 'Detalhe calendário');
          },
        ),
      );
      streams.controllers.single.add(
        _snapshot([
          (
            id: 'multiday-public-event',
            data: {
              'title': 'Festival de três dias',
              'category': 'Cultura',
              'eventDate': _localDate(start),
              'endDate': _localDate(end),
              'startTime': '18:30',
              'endTime': '22:00',
              'imageUrl': 'https://images.example.invalid/festival.jpg',
              'published': true,
              'active': true,
            },
          ),
          (
            id: 'draft-event',
            data: {
              'title': 'Evento privado',
              'eventDate': _localDate(day),
              'published': false,
              'active': true,
            },
          ),
        ]),
      );
      await tester.pump();
      await tester.tap(find.text('Calendário'));
      await tester.pump();
      final currentMonth = DateTime.now();
      if (day.year != currentMonth.year || day.month != currentMonth.month) {
        await tester.tap(find.byKey(const ValueKey('city-calendar-next')));
        await tester.pump();
      }
      final dayKey = 'calendar-day-${_localDate(day)}';
      await tester.ensureVisible(find.byKey(ValueKey(dayKey)));
      await tester.tap(find.byKey(ValueKey(dayKey)));
      await tester.pump();

      expect(
        find.byKey(ValueKey('calendar-dot-${_localDate(day)}')),
        findsOneWidget,
      );
      expect(find.text('Festival de três dias'), findsOneWidget);
      expect(find.text('Cultura'), findsOneWidget);
      expect(find.text('18:30 · até 22:00'), findsOneWidget);
      expect(find.text('Evento privado'), findsNothing);
      expect(find.byType(Image), findsOneWidget);

      await tester.tap(find.text('Detalhes'));
      await tester.pumpAndSettle();
      expect(resolvedId, 'multiday-public-event');
      expect(find.text('Detalhe calendário'), findsOneWidget);
    },
  );

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

  testWidgets(
    'agenda separates future and ended events and excludes invalid dates',
    (tester) async {
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
      expect(find.text('Encerrados'), findsOneWidget);
      expect(find.text('Evento passado'), findsOneWidget);
      expect(find.text('Evento com data inválida'), findsNothing);
    },
  );

  testWidgets(
    'agenda search and category filters show matching published items',
    (tester) async {
      final streams = _EventStreams();
      await tester.pumpWidget(_app(streams));
      final future = DateTime.now().add(const Duration(days: 4));
      streams.controllers.single.add(
        _snapshot([
          (
            id: 'event-culture',
            data: {
              'title': 'Feira de Artesanato',
              'category': 'Cultura',
              'description': 'Artes locais',
              'eventDate': future.toIso8601String(),
              'published': true,
              'active': true,
            },
          ),
          (
            id: 'event-sport',
            data: {
              'title': 'Corrida Comunitária',
              'category': 'Esportes',
              'eventDate': future.toIso8601String(),
              'published': true,
              'active': true,
            },
          ),
          (
            id: 'event-draft',
            data: {
              'title': 'Rascunho de Teatro',
              'category': 'Cultura',
              'eventDate': future.toIso8601String(),
              'published': false,
              'active': true,
            },
          ),
        ]),
      );
      await tester.pump();

      await tester.tap(find.text('Cultura'));
      await tester.pump();
      expect(find.text('Feira de Artesanato'), findsOneWidget);
      expect(find.text('Corrida Comunitária'), findsNothing);
      expect(find.text('Rascunho de Teatro'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('city-event-search')),
        'artesanato',
      );
      await tester.pump();
      expect(find.text('Feira de Artesanato'), findsOneWidget);
      expect(find.text('Corrida Comunitária'), findsNothing);
    },
  );

  testWidgets('offset dates are grouped by their local calendar day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

    expect(
      find.byKey(const ValueKey('agenda-group-title-Hoje')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agenda-group-title-Amanhã')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agenda-group-title-Próximos')),
      findsOneWidget,
    );
    _expectTextOrder(tester, const [
      'Evento hoje com offset',
      'Evento amanhã com offset',
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

    expect(find.text('Hoje'), findsNWidgets(2));
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
    tester.view.physicalSize = const Size(720, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    expect(find.text('Próximos'), findsNWidgets(2));
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

  testWidgets('date filters include today spans and order future starts', (
    tester,
  ) async {
    final streams = _EventStreams();
    final now = DateTime.utc(2026, 11, 5, 2, 30); // Nov 4, 23:30 in Brasília.
    await tester.pumpWidget(_app(streams, clock: () => now));
    streams.controllers.single.add(
      _snapshot([
        (
          id: 'tomorrow-late',
          data: {
            'title': 'Amanhã à noite',
            'category': 'Cultura',
            'eventDate': '2026-11-05',
            'startTime': '20:00',
            'published': true,
            'active': true,
          },
        ),
        (
          id: 'spanning-today',
          data: {
            'title': 'Festival em vários dias',
            'category': 'Cultura',
            'eventDate': '2026-11-03',
            'endDate': '2026-11-05',
            'startTime': '18:00',
            'endTime': '23:59',
            'published': true,
            'active': true,
          },
        ),
        (
          id: 'today-future',
          data: {
            'title': 'Começa antes da meia-noite',
            'category': 'Cultura',
            'eventDate': '2026-11-04',
            'startTime': '23:45',
            'endTime': '23:59',
            'published': true,
            'active': true,
          },
        ),
        (
          id: 'tomorrow-early',
          data: {
            'title': 'Amanhã de manhã',
            'category': 'Cultura',
            'eventDate': '2026-11-05',
            'startTime': '08:00',
            'published': true,
            'active': true,
          },
        ),
        (
          id: 'tomorrow-race',
          data: {
            'title': 'Corrida amanhã',
            'category': 'Esportes',
            'eventDate': '2026-11-05',
            'startTime': '09:00',
            'published': true,
            'active': true,
          },
        ),
        (
          id: 'ended-today',
          data: {
            'title': 'Já encerrado hoje',
            'category': 'Cultura',
            'eventDate': '2026-11-04',
            'endTime': '22:00',
            'published': true,
            'active': true,
          },
        ),
        (
          id: 'missing-date',
          data: {'title': 'Evento sem data', 'published': true, 'active': true},
        ),
        (
          id: 'invalid-date',
          data: {
            'title': 'Evento com data inválida',
            'eventDate': '31/02/2026',
            'published': true,
            'active': true,
          },
        ),
      ]),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('city-event-date-filter-all')),
      findsOneWidget,
    );
    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('A acontecer'), findsOneWidget);
    expect(find.text('Histórico'), findsOneWidget);
    expect(find.text('Evento sem data'), findsNothing);
    expect(find.text('Evento com data inválida'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('city-event-date-filter-today')),
    );
    await tester.pump();
    expect(find.text('Festival em vários dias'), findsOneWidget);
    expect(find.text('Começa antes da meia-noite'), findsOneWidget);
    expect(find.text('Já encerrado hoje'), findsNothing);
    expect(find.text('Amanhã de manhã'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('city-event-date-filter-upcoming')),
    );
    await tester.pump();
    _expectTextOrder(tester, [
      'Começa antes da meia-noite',
      'Amanhã de manhã',
      'Corrida amanhã',
      'Amanhã à noite',
    ]);
    expect(find.text('Festival em vários dias'), findsNothing);
    expect(find.text('Já encerrado hoje'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Cultura'));
    await tester.enterText(
      find.byKey(const ValueKey('city-event-search')),
      'amanhã',
    );
    await tester.pump();
    expect(find.text('Amanhã de manhã'), findsOneWidget);
    expect(find.text('Amanhã à noite'), findsOneWidget);
    expect(find.text('Corrida amanhã'), findsNothing);
    expect(find.text('Começa antes da meia-noite'), findsNothing);

    await tester.tap(find.byTooltip('Limpar busca'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Todas as categorias'));
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('city-event-date-filter-happening')),
    );
    await tester.pump();
    expect(find.text('Festival em vários dias'), findsOneWidget);
    expect(find.text('Começa antes da meia-noite'), findsOneWidget);
    expect(find.text('Já encerrado hoje'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('city-event-date-filter-ended')),
    );
    await tester.pump();
    expect(find.text('Já encerrado hoje'), findsOneWidget);
    expect(find.text('Festival em vários dias'), findsNothing);
  });

  testWidgets('event date filters fit narrow layouts with enlarged text', (
    tester,
  ) async {
    for (final width in <double>[320, 360, 412]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: CityAgendaView(
            eventsStreamFactory: () => Stream.value(
              _snapshot([
                (
                  id: 'responsive-event',
                  data: {
                    'title': 'Evento responsivo',
                    'eventDate': '2031-07-08',
                    'published': true,
                    'active': true,
                  },
                ),
              ]),
            ),
            clock: () => DateTime.utc(2031, 7, 1, 15),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final filter in ['all', 'today', 'upcoming', 'happening', 'ended']) {
        expect(
          find.byKey(ValueKey('city-event-date-filter-$filter')),
          findsOneWidget,
        );
      }
      await tester.tap(
        find.byKey(const ValueKey('city-event-date-filter-today')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Não há eventos acontecendo hoje.'), findsOneWidget);
      final layoutError = tester.takeException();
      expect(layoutError, isNull, reason: 'width=$width');
    }
    await tester.binding.setSurfaceSize(null);
  });
}
