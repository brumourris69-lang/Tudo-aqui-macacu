import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/features/tourism/widgets/tourism_overview.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

// ignore: subtype_of_sealed_class
class _DocumentReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Home tourism shortcut shows its selected category from loaded spots', (
    tester,
  ) async {
    final snapshot = PublicContentSnapshot([
      PublicContentDocument(
        'trail-1',
        {
          'title': 'Trilha de teste',
          'category': 'trilhas',
          'published': true,
          'active': true,
        },
        _DocumentReference(),
      ),
      PublicContentDocument(
        'waterfall-1',
        {
          'title': 'Cachoeira de teste',
          'category': 'cachoeiras',
          'published': true,
          'active': true,
        },
        _DocumentReference(),
      ),
    ]);
    var routeSubscriptions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TourismHomeView(
          initialCategoryKey: 'trilhas',
          routesStreamFactory: () {
            routeSubscriptions++;
            return Stream.value(snapshot);
          },
          configStreamFactory: () => Stream.value(null),
          adminOverride: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(TourismCategoryView), findsOneWidget);
    expect(find.text('Trilha de teste'), findsOneWidget);
    expect(find.text('Cachoeira de teste'), findsNothing);
    expect(routeSubscriptions, 1);
  });

  testWidgets('selected Tourism category retains cached spots on refresh error and retries', (
    tester,
  ) async {
    final previous = PublicContentSnapshot([
      PublicContentDocument(
        'trail-cached',
        {
          'title': 'Trilha em cache',
          'category': 'trilhas',
          'published': true,
          'active': true,
        },
        _DocumentReference(),
      ),
    ]);
    final refreshed = PublicContentSnapshot([
      PublicContentDocument(
        'trail-refreshed',
        {
          'title': 'Trilha atualizada',
          'category': 'trilhas',
          'published': true,
          'active': true,
        },
        _DocumentReference(),
      ),
    ]);
    var attempts = 0;
    Stream<PublicContentSnapshot> firstAttempt() async* {
      yield previous;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      throw StateError('offline');
    }

    await tester.pumpWidget(
      MaterialApp(
        home: TourismHomeView(
          initialCategoryKey: 'trilhas',
          routesStreamFactory: () => ++attempts == 1
              ? firstAttempt()
              : Stream.value(refreshed),
          configStreamFactory: () => Stream.value(null),
          adminOverride: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('Trilha em cache'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Trilha em cache'), findsOneWidget);
    expect(find.textContaining('Não foi possível atualizar'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Trilha atualizada'), findsOneWidget);
    expect(find.text('Trilha em cache'), findsNothing);
    expect(find.textContaining('Não foi possível atualizar'), findsNothing);
    expect(attempts, 2);
  });

  testWidgets('selected Tourism category stays selected through initial error and retry', (
    tester,
  ) async {
    final failedFirstRead = StreamController<PublicContentSnapshot>();
    final recovered = PublicContentSnapshot([
      PublicContentDocument(
        'trail-recovered',
        {
          'title': 'Trilha recuperada',
          'category': 'trilhas',
          'published': true,
          'active': true,
        },
        _DocumentReference(),
      ),
      PublicContentDocument(
        'waterfall-recovered',
        {
          'title': 'Cachoeira recuperada',
          'category': 'cachoeiras',
          'published': true,
          'active': true,
        },
        _DocumentReference(),
      ),
    ]);
    var attempts = 0;
    Stream<PublicContentSnapshot> loadRoutes() => ++attempts == 1
        ? failedFirstRead.stream
        : Stream.value(recovered);

    await tester.pumpWidget(
      MaterialApp(
        home: TourismHomeView(
          initialCategoryKey: 'trilhas',
          routesStreamFactory: loadRoutes,
          configStreamFactory: () => Stream.value(null),
          adminOverride: false,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Trilhas'), findsAtLeastNWidgets(1));
    expect(find.byType(TourismOverview), findsNothing);
    expect(find.text('Carregando locais de Trilhas…'), findsOneWidget);

    failedFirstRead.addError(StateError('offline'));
    await tester.pump();
    expect(find.text('Trilhas'), findsAtLeastNWidgets(1));
    expect(find.byType(TourismOverview), findsNothing);
    expect(find.text('Não foi possível carregar os locais de Trilhas.'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(TourismCategoryView), findsOneWidget);
    expect(find.text('Trilha recuperada'), findsOneWidget);
    expect(find.text('Cachoeira recuperada'), findsNothing);
    expect(attempts, 2);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    unawaited(failedFirstRead.close());
  });
}
