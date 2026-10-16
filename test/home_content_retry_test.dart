import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

// ignore: subtype_of_sealed_class
class _Reference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PublicContentSnapshot _snapshot(String title) => PublicContentSnapshot([
  PublicContentDocument('fixture-event', {
    'title': title,
    'active': true,
  }, _Reference()),
]);

class _SnapshotStreams {
  final controllers = <StreamController<PublicContentSnapshot>>[];

  Stream<PublicContentSnapshot> create() {
    final controller = StreamController<PublicContentSnapshot>();
    controllers.add(controller);
    return controller.stream;
  }
}

Widget _eventApp(_SnapshotStreams streams) => MaterialApp(
  home: Scaffold(body: EventCard(eventsStreamFactory: streams.create)),
);

void main() {
  testWidgets('ad carousel distinguishes initial failure and retries', (
    tester,
  ) async {
    final streams = _SnapshotStreams();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdCarousel(adsSnapshotStreamFactory: streams.create),
        ),
      ),
    );
    expect(find.text('Carregando anúncios…'), findsOneWidget);
    streams.controllers.single.addError(StateError('offline'));
    await tester.pump();

    expect(find.text('Não foi possível carregar os anúncios.'), findsOneWidget);
    expect(find.text('Anuncie aqui'), findsNothing);
    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(streams.controllers, hasLength(2));
    streams.controllers[1].add(PublicContentSnapshot([]));
    await tester.pump();

    expect(find.text('Não foi possível carregar os anúncios.'), findsNothing);
    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('ad refresh failure keeps prior ads and can recover', (
    tester,
  ) async {
    final streams = _SnapshotStreams();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdCarousel(adsSnapshotStreamFactory: streams.create),
        ),
      ),
    );
    streams.controllers.single.add(_snapshot('Anúncio ativo'));
    await tester.pump();
    expect(find.bySemanticsLabel('Anúncio ativo'), findsOneWidget);
    streams.controllers[0].addError(StateError('refresh failed'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(PageView), findsOneWidget);
    expect(
      find.text('Não foi possível atualizar os anúncios.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    streams.controllers[1].add(_snapshot('Anúncio atualizado'));
    await tester.pump();
    streams.controllers[0].add(_snapshot('Anúncio atrasado'));
    await tester.pump();

    expect(find.text('Não foi possível atualizar os anúncios.'), findsNothing);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.bySemanticsLabel('Anúncio atualizado'), findsOneWidget);
    expect(find.bySemanticsLabel('Anúncio atrasado'), findsNothing);
  });

  testWidgets('event agenda distinguishes failure and retries successfully', (
    tester,
  ) async {
    final streams = _SnapshotStreams();
    await tester.pumpWidget(_eventApp(streams));
    streams.controllers.single.addError(StateError('offline'));
    await tester.pump();

    expect(find.text('Agenda indisponível no momento'), findsOneWidget);
    expect(find.byTooltip('Tentar novamente'), findsOneWidget);
    await tester.tap(find.byTooltip('Tentar novamente'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(streams.controllers, hasLength(2));
    streams.controllers[1].add(_snapshot('Evento recuperado'));
    await tester.pump();

    expect(find.text('Evento recuperado'), findsOneWidget);
    expect(find.text('Não foi possível atualizar a agenda.'), findsNothing);
  });

  testWidgets('event refresh failure keeps previous event and recovers', (
    tester,
  ) async {
    final streams = _SnapshotStreams();
    await tester.pumpWidget(_eventApp(streams));
    streams.controllers.single.add(_snapshot('Evento anterior'));
    await tester.pump();
    streams.controllers[0].addError(StateError('refresh failed'));
    await tester.pump();

    expect(find.text('Evento anterior'), findsOneWidget);
    expect(find.text('Não foi possível atualizar a agenda.'), findsOneWidget);
    await tester.tap(find.byTooltip('Tentar novamente'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    streams.controllers[1].add(_snapshot('Evento atualizado'));
    await tester.pump();
    streams.controllers[0].add(_snapshot('Evento atrasado'));
    await tester.pump();

    expect(find.text('Evento atualizado'), findsOneWidget);
    expect(find.text('Não foi possível atualizar a agenda.'), findsNothing);
    expect(find.text('Evento atrasado'), findsNothing);
  });

  testWidgets('successful empty event response is distinct from failure', (
    tester,
  ) async {
    final streams = _SnapshotStreams();
    await tester.pumpWidget(_eventApp(streams));
    streams.controllers.single.add(PublicContentSnapshot([]));
    await tester.pump();

    expect(find.text('Nenhum evento publicado no momento'), findsOneWidget);
    expect(find.byTooltip('Tentar novamente'), findsNothing);
    expect(find.text('Agenda indisponível no momento'), findsNothing);
  });
}
