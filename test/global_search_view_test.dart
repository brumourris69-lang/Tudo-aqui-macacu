import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/features/jobs/models/public_job.dart';
import 'package:tudo_aqui_macacu/features/jobs/pages/job_detail_page.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

// ignore: subtype_of_sealed_class
class _DocumentReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PublicContentSnapshot _snapshot(
  List<({String id, Map<String, dynamic> data})> documents,
) => PublicContentSnapshot([
  for (final document in documents)
    PublicContentDocument(document.id, document.data, _DocumentReference()),
]);

Finder _resultTile(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile));

GlobalSearchViewDependencies _dependencies({
  Map<String, List<({String id, Map<String, dynamic> data})>> documents =
      const {},
  Future<void> Function()? verifyIsolation,
  Future<PublicJob?> Function(String id)? resolveJob,
  Future<PublicContentSnapshot> Function(String collection)? loadContent,
  Future<void> Function()? onLoadBusinesses,
}) => GlobalSearchViewDependencies(
  loadBusinesses: () async {
    await onLoadBusinesses?.call();
    return const [];
  },
  loadContent:
      loadContent ??
      (collection) async => _snapshot(documents[collection] ?? const []),
  verifyLocalIsolation: verifyIsolation ?? () async {},
  resolveJob:
      resolveJob ?? (id) async => PublicJob(id: id, title: 'Detalhe $id'),
);

void main() {
  final isLocalBuild = LocalSearchEnvironment.enabled;

  testWidgets(
    'job result uses its real collection and ID, opens after isolation, and returns to cached results',
    (tester) async {
      final calls = <String>[];
      final collectionReads = <String, int>{};
      final dependencies = _dependencies(
        verifyIsolation: () async => calls.add('isolation'),
        resolveJob: (id) async {
          calls.add('resolve:$id');
          return PublicJob(id: id, title: 'Detalhe correto de $id');
        },
        loadContent: (collection) async {
          collectionReads.update(
            collection,
            (previous) => previous + 1,
            ifAbsent: () => 1,
          );
          return _snapshot(
            {
                  'jobs': [
                    (
                      id: 'same-id',
                      data: {
                        'title': 'Passeio e oportunidade de vaga',
                        'description': 'Conteúdo fictício para pesquisa',
                        'link': 'https://example.com/nao-usar-como-id',
                      },
                    ),
                  ],
                  'events': [
                    (
                      id: 'same-id',
                      data: {
                        'title': 'Passeio cultural',
                        'description': 'Evento',
                      },
                    ),
                  ],
                }[collection] ??
                const [],
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: GlobalSearchView(dependencies: dependencies)),
      );
      await tester.enterText(find.byType(TextField), 'passeio');
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ListTile>(_resultTile('Passeio e oportunidade de vaga'))
            .key,
        const ValueKey<String?>('jobs/same-id'),
      );
      expect(
        tester.widget<ListTile>(_resultTile('Passeio cultural')).key,
        const ValueKey<String?>('events/same-id'),
      );
      expect(collectionReads.values, everyElement(1));

      await tester.tap(_resultTile('Passeio e oportunidade de vaga'));
      await tester.pumpAndSettle();

      expect(calls, ['isolation', 'resolve:same-id']);
      expect(find.byType(JobDetailPage), findsOneWidget);
      expect(find.text('Detalhe correto de same-id'), findsOneWidget);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'passeio',
      );
      expect(find.text('Passeio e oportunidade de vaga'), findsOneWidget);
      expect(find.text('Passeio cultural'), findsOneWidget);
      expect(collectionReads.values, everyElement(1));
    },
    skip: !isLocalBuild,
  );

  testWidgets(
    'isolation failure does not open a job detail or call the resolver',
    (tester) async {
      var resolverCalls = 0;
      final dependencies = _dependencies(
        documents: {
          'jobs': [
            (id: 'job-1', data: {'title': 'Vaga teste'}),
          ],
        },
        verifyIsolation: () async => throw StateError('isolation unavailable'),
        resolveJob: (_) async {
          resolverCalls++;
          return null;
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: GlobalSearchView(dependencies: dependencies)),
      );
      await tester.enterText(find.byType(TextField), 'vaga');
      await tester.pumpAndSettle();
      await tester.tap(_resultTile('Vaga teste'));
      await tester.pumpAndSettle();

      expect(find.byType(JobDetailPage), findsNothing);
      expect(resolverCalls, 0);
      expect(
        find.text('Não foi possível validar o ambiente local.'),
        findsOneWidget,
      );
    },
    skip: !isLocalBuild,
  );

  testWidgets('unavailable job detail remains a controlled unavailable state', (
    tester,
  ) async {
    final dependencies = _dependencies(
      documents: {
        'jobs': [
          (id: 'removed-job', data: {'title': 'Vaga removida'}),
        ],
      },
      resolveJob: (_) async => null,
    );
    await tester.pumpWidget(
      MaterialApp(home: GlobalSearchView(dependencies: dependencies)),
    );
    await tester.enterText(find.byType(TextField), 'vaga');
    await tester.pumpAndSettle();
    await tester.tap(_resultTile('Vaga removida'));
    await tester.pumpAndSettle();

    expect(find.text('Esta vaga não está mais disponível.'), findsOneWidget);
  }, skip: !isLocalBuild);

  testWidgets(
    'normal app preserves the current job action without resolving details',
    (tester) async {
      var resolverCalls = 0;
      var isolationCalls = 0;
      final dependencies = _dependencies(
        documents: {
          'jobs': [
            (id: 'job-normal', data: {'title': 'Vaga normal'}),
          ],
        },
        verifyIsolation: () async => isolationCalls++,
        resolveJob: (_) async {
          resolverCalls++;
          return PublicJob(id: 'job-normal', title: 'Não deve abrir');
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: GlobalSearchView(dependencies: dependencies)),
      );
      await tester.enterText(find.byType(TextField), 'vaga');
      await tester.pumpAndSettle();
      await tester.tap(_resultTile('Vaga normal'));
      await tester.pumpAndSettle();

      expect(find.byType(JobDetailPage), findsNothing);
      expect(find.text('Conteúdo publicado em Vagas.'), findsOneWidget);
      expect(resolverCalls, 0);
      expect(isolationCalls, 0);
    },
    skip: isLocalBuild,
  );

  testWidgets('other collection links keep the existing local link handling', (
    tester,
  ) async {
    final dependencies = _dependencies(
      documents: {
        'news': [
          (
            id: 'news-id',
            data: {
              'title': 'Notícia com link',
              'link': 'https://example.com/news',
            },
          ),
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: GlobalSearchView(dependencies: dependencies)),
    );
    await tester.enterText(find.byType(TextField), 'notícia');
    await tester.pumpAndSettle();
    await tester.tap(_resultTile('Notícia com link'));
    await tester.pumpAndSettle();

    expect(find.byType(JobDetailPage), findsNothing);
    expect(
      find.text('Links externos indisponíveis no ambiente local.'),
      findsOneWidget,
    );
  }, skip: !isLocalBuild);

  testWidgets('same-term rebuild reuses one search and newer query wins', (
    tester,
  ) async {
    final readCounts = <String, int>{};
    var businessReads = 0;
    final oldJobs = Completer<PublicContentSnapshot>();
    final newJobs = Completer<PublicContentSnapshot>();
    late StateSetter rebuildHost;
    final dependencies = _dependencies(
      onLoadBusinesses: () async => businessReads++,
      loadContent: (collection) async {
        readCounts.update(
          collection,
          (previous) => previous + 1,
          ifAbsent: () => 1,
        );
        if (collection == 'jobs') {
          return readCounts[collection] == 1 ? oldJobs.future : newJobs.future;
        }
        return _snapshot(const []);
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuildHost = setState;
            return GlobalSearchView(dependencies: dependencies);
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump();
    expect(readCounts.values, everyElement(2));
    expect(businessReads, 2);

    newJobs.complete(
      _snapshot([
        (id: 'beta-id', data: {'title': 'Beta opportunity'}),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beta opportunity'), findsOneWidget);

    rebuildHost(() {});
    await tester.pumpAndSettle();
    expect(readCounts.values, everyElement(2));
    expect(businessReads, 2);

    oldJobs.complete(
      _snapshot([
        (id: 'alpha-id', data: {'title': 'Alpha opportunity'}),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beta opportunity'), findsOneWidget);
    expect(find.text('Alpha opportunity'), findsNothing);
  });
}
