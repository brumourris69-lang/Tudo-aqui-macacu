import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';
import 'package:tudo_aqui_macacu/features/jobs/models/public_job.dart';
import 'package:tudo_aqui_macacu/features/jobs/pages/job_detail_page.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/public_job_details_repository.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

// ignore: subtype_of_sealed_class
class _DocumentReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PublicContentSnapshot _snapshot(List<Map<String, dynamic>> items) =>
    PublicContentSnapshot([
      for (var i = 0; i < items.length; i++)
        PublicContentDocument('id-$i', items[i], _DocumentReference()),
    ]);

PublicContentSnapshot _snapshotWithIds(
  List<({String id, Map<String, dynamic> data})> items,
) => PublicContentSnapshot([
  for (final item in items)
    PublicContentDocument(item.id, item.data, _DocumentReference()),
]);

class _ContentStreams {
  final controllers = <StreamController<PublicContentSnapshot>>[];
  final collections = <String>[];
  int active = 0;
  int maxActive = 0;

  Stream<PublicContentSnapshot> create(String collection) {
    collections.add(collection);
    late StreamController<PublicContentSnapshot> controller;
    controller = StreamController<PublicContentSnapshot>(
      onListen: () {
        active++;
        if (active > maxActive) maxActive = active;
      },
      onCancel: () => active--,
    );
    controllers.add(controller);
    return controller.stream;
  }
}

Widget _app({
  required _ContentStreams streams,
  String collection = 'jobs',
  String empty = 'Não há vagas publicadas no momento.',
}) => MaterialApp(
  home: Scaffold(
    body: FirestoreContentList(
      collection: collection,
      empty: empty,
      streamFactory: streams.create,
    ),
  ),
);

void main() {
  final isLocalBuild = LocalSearchEnvironment.enabled;

  testWidgets('shows loading until a successful response has results', (
    tester,
  ) async {
    final streams = _ContentStreams();
    await tester.pumpWidget(_app(streams: streams));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    streams.controllers.single.add(
      _snapshot([
        {'title': 'Vaga fictícia', 'published': true},
      ]),
    );
    await tester.pump();

    expect(find.text('Vaga fictícia'), findsOneWidget);
    expect(find.text('Não há vagas publicadas no momento.'), findsNothing);
  });

  testWidgets('shows the empty message only after an empty success', (
    tester,
  ) async {
    final streams = _ContentStreams();
    await tester.pumpWidget(_app(streams: streams));
    expect(find.text('Não há vagas publicadas no momento.'), findsNothing);

    streams.controllers.single.add(_snapshot([]));
    await tester.pump();

    expect(find.text('Não há vagas publicadas no momento.'), findsOneWidget);
    expect(find.text('Não foi possível carregar este conteúdo.'), findsNothing);
  });

  testWidgets('shows a retry action after the first request fails', (
    tester,
  ) async {
    final streams = _ContentStreams();
    await tester.pumpWidget(_app(streams: streams));
    streams.controllers.single.addError(StateError('internal backend data'));
    await tester.pump();

    expect(
      find.text('Não foi possível carregar este conteúdo.'),
      findsOneWidget,
    );
    expect(find.textContaining('internal backend data'), findsNothing);
    expect(find.text('Não há vagas publicadas no momento.'), findsNothing);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('retry starts one fresh subscription and recovers', (
    tester,
  ) async {
    final streams = _ContentStreams();
    await tester.pumpWidget(_app(streams: streams));
    streams.controllers.single.addError(StateError('offline'));
    await tester.pump();

    await tester.tap(find.text('Tentar novamente'));
    await tester.idle();
    await tester.pump();
    expect(streams.controllers, hasLength(2));
    expect(streams.collections, ['jobs', 'jobs']);
    expect(streams.active, 1);
    expect(streams.maxActive, 1);

    streams.controllers[1].add(
      _snapshot([
        {'title': 'Recuperada', 'published': true},
      ]),
    );
    await tester.pump();
    expect(find.text('Recuperada'), findsOneWidget);
    expect(find.text('Não foi possível carregar este conteúdo.'), findsNothing);
  });

  testWidgets(
    'keeps previous results on refresh error and clears warning on recovery',
    (tester) async {
      final streams = _ContentStreams();
      await tester.pumpWidget(_app(streams: streams));
      streams.controllers.single.add(
        _snapshot([
          {'title': 'Vaga mantida', 'published': true},
        ]),
      );
      await tester.pump();

      streams.controllers.single.addError(StateError('temporary outage'));
      await tester.pump();
      expect(find.text('Vaga mantida'), findsOneWidget);
      expect(
        find.text('Não foi possível atualizar. Tente novamente.'),
        findsOneWidget,
      );

      streams.controllers.single.add(
        _snapshot([
          {'title': 'Vaga atualizada', 'published': true},
        ]),
      );
      await tester.pump();
      expect(find.text('Vaga atualizada'), findsOneWidget);
      expect(
        find.text('Não foi possível atualizar. Tente novamente.'),
        findsNothing,
      );
    },
  );

  testWidgets('switching collection replaces and cancels the active stream', (
    tester,
  ) async {
    final streams = _ContentStreams();
    await tester.pumpWidget(_app(streams: streams));
    streams.controllers.single.add(
      _snapshot([
        {'title': 'Vaga', 'published': true},
      ]),
    );
    await tester.pump();

    await tester.pumpWidget(_app(streams: streams, collection: 'news'));
    await tester.idle();
    await tester.pump();

    expect(streams.collections, ['jobs', 'news']);
    expect(streams.active, 1);
    expect(streams.maxActive, 1);
    expect(find.text('Vaga'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    streams.controllers.first.add(
      _snapshot([
        {'title': 'Resposta antiga', 'published': true},
      ]),
    );
    await tester.pump();
    expect(find.text('Resposta antiga'), findsNothing);

    streams.controllers.last.add(
      _snapshot([
        {'title': 'Notícia atual', 'published': true},
      ]),
    );
    await tester.pump();
    expect(find.text('Notícia atual'), findsOneWidget);
  });

  testWidgets('discarding the list cancels its only active subscription', (
    tester,
  ) async {
    final streams = _ContentStreams();
    await tester.pumpWidget(_app(streams: streams));
    expect(streams.active, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(streams.active, 0);
  });

  testWidgets(
    'demo job cards preserve each document ID and resolve the selected job',
    (tester) async {
      final streams = _ContentStreams();
      final resolvedIds = <String>[];
      final detailsRepository = PublicJobDetailsRepository(
        resolveJob: (id) async {
          resolvedIds.add(id);
          return PublicJob(id: id, title: 'Detalhe de $id');
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LocalJobsView(
            streamFactory: streams.create,
            jobDetailsRepository: detailsRepository,
          ),
        ),
      );
      streams.controllers.single.add(
        _snapshotWithIds([
          (
            id: 'filtered-out-job',
            data: {'title': 'Vaga não publicada', 'published': false},
          ),
          (
            id: 'job-first',
            data: {'title': 'Primeira vaga', 'published': true},
          ),
          (
            id: 'job-second',
            data: {
              'title': 'Segunda vaga',
              'published': true,
              'contact': 'contato privado fictício',
              'phone': 'telefone privado fictício',
              'whatsapp': 'WhatsApp privado fictício',
              'link': 'https://example.com/contato-privado',
            },
          ),
        ]),
      );
      await tester.pump();

      final secondCard = find.ancestor(
        of: find.text('Segunda vaga'),
        matching: find.byType(LocalContentCard),
      );
      await tester.tap(
        find.descendant(of: secondCard, matching: find.text('Ver vaga')),
      );
      await tester.pumpAndSettle();

      expect(resolvedIds, ['job-second']);
      expect(streams.collections, ['jobs']);
      expect(find.byType(JobDetailPage), findsOneWidget);
      expect(find.text('Detalhe de job-second'), findsOneWidget);
      expect(find.textContaining('privado fictício'), findsNothing);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Primeira vaga'), findsOneWidget);
      expect(find.text('Segunda vaga'), findsOneWidget);
      expect(streams.active, 1);
    },
    skip: !isLocalBuild,
  );

  testWidgets(
    'demo job with no longer available detail stays on controlled state',
    (tester) async {
      final streams = _ContentStreams();
      final detailsRepository = PublicJobDetailsRepository(
        resolveJob: (_) async => null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LocalJobsView(
            streamFactory: streams.create,
            jobDetailsRepository: detailsRepository,
          ),
        ),
      );
      streams.controllers.single.add(
        _snapshotWithIds([
          (
            id: 'removed-job',
            data: {'title': 'Vaga removida', 'published': true},
          ),
        ]),
      );
      await tester.pump();
      await tester.tap(find.text('Ver vaga'));
      await tester.pumpAndSettle();

      expect(find.text('Esta vaga não está mais disponível.'), findsOneWidget);
    },
    skip: !isLocalBuild,
  );

  testWidgets(
    'job that expires after listing opens as unavailable and returns to the list',
    (tester) async {
      final streams = _ContentStreams();
      final resolvedIds = <String>[];
      final detailsRepository = PublicJobDetailsRepository(
        resolveJob: (id) async {
          resolvedIds.add(id);
          // getPublicJob revalidates visibility; an expired job is unavailable.
          return null;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LocalJobsView(
            streamFactory: streams.create,
            jobDetailsRepository: detailsRepository,
          ),
        ),
      );
      streams.controllers.single.add(
        _snapshotWithIds([
          (
            id: 'job-expired-after-listing',
            data: {
              'title': 'Vaga que expirou',
              'description': 'Resumo ainda disponível na lista',
              'published': true,
              'active': true,
            },
          ),
        ]),
      );
      await tester.pump();

      await tester.tap(find.text('Ver vaga'));
      await tester.pumpAndSettle();

      expect(resolvedIds, ['job-expired-after-listing']);
      expect(find.text('Esta vaga não está mais disponível.'), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Vaga que expirou'), findsOneWidget);
      expect(streams.active, 1);
    },
    skip: !isLocalBuild,
  );

  testWidgets(
    'job detail retries after a network error, hides unapproved fields, and returns to the same list',
    (tester) async {
      final streams = _ContentStreams();
      var resolverCalls = 0;
      final detailsRepository = PublicJobDetailsRepository(
        resolveJob: (id) async {
          expect(id, 'job-retry-private-fields');
          resolverCalls++;
          if (resolverCalls == 1) throw StateError('network unavailable');
          return const PublicJob(
            id: 'job-retry-private-fields',
            title: 'Vaga recuperada',
            description: 'Descrição pública completa',
            category: 'Atendimento',
            location: 'Cachoeiras de Macacu',
            company: 'Empresa pública',
            employmentType: 'Presencial',
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LocalJobsView(
            streamFactory: streams.create,
            jobDetailsRepository: detailsRepository,
          ),
        ),
      );
      streams.controllers.single.add(
        _snapshotWithIds([
          (
            id: 'job-retry-private-fields',
            data: {
              'title': 'Vaga protegida',
              'description': 'Resumo público',
              'category': 'Atendimento',
              'location': 'Cachoeiras de Macacu',
              'company': 'Empresa pública',
              'employmentType': 'Presencial',
              'published': true,
              'active': true,
              'contact': 'private-sentinel-contact-1',
              'phone': 'private-sentinel-phone-2',
              'whatsapp': 'private-sentinel-whatsapp-3',
              'link': 'private-sentinel-link-4',
              'instagram': 'private-sentinel-instagram-5',
              'maps': 'private-sentinel-maps-6',
              'mapsUrl': 'private-sentinel-mapsurl-7',
              'additionalInfo': 'private-sentinel-additional-8',
              'salary': 'unapproved-sentinel-salary-9',
              'eventDate': 'unapproved-sentinel-eventdate-10',
              'date': 'unapproved-sentinel-date-11',
              'unknownAdminField': 'unapproved-sentinel-unknown-12',
            },
          ),
        ]),
      );
      await tester.pump();

      final card = find.ancestor(
        of: find.text('Vaga protegida'),
        matching: find.byType(LocalContentCard),
      );
      for (final sentinel in [
        'private-sentinel-contact-1',
        'private-sentinel-phone-2',
        'private-sentinel-whatsapp-3',
        'private-sentinel-link-4',
        'private-sentinel-instagram-5',
        'private-sentinel-maps-6',
        'private-sentinel-mapsurl-7',
        'private-sentinel-additional-8',
        'unapproved-sentinel-salary-9',
        'unapproved-sentinel-eventdate-10',
        'unapproved-sentinel-date-11',
        'unapproved-sentinel-unknown-12',
      ]) {
        expect(find.textContaining(sentinel), findsNothing);
      }
      expect(
        find.descendant(of: card, matching: find.text('Ver vaga')),
        findsOneWidget,
      );

      await tester.tap(find.text('Ver vaga'));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível carregar esta vaga.'), findsOneWidget);
      expect(find.text('network unavailable'), findsNothing);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(resolverCalls, 2);
      expect(find.text('Vaga recuperada'), findsOneWidget);
      expect(find.text('Descrição pública completa'), findsOneWidget);
      for (final sentinel in [
        'private-sentinel-contact-1',
        'private-sentinel-phone-2',
        'private-sentinel-whatsapp-3',
        'private-sentinel-link-4',
        'private-sentinel-instagram-5',
        'private-sentinel-maps-6',
        'private-sentinel-mapsurl-7',
        'private-sentinel-additional-8',
        'unapproved-sentinel-salary-9',
        'unapproved-sentinel-eventdate-10',
        'unapproved-sentinel-date-11',
        'unapproved-sentinel-unknown-12',
      ]) {
        expect(find.textContaining(sentinel), findsNothing);
      }

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Vaga protegida'), findsOneWidget);
      expect(streams.collections, ['jobs']);
      expect(streams.active, 1);
      expect(resolverCalls, 2);
    },
    skip: !isLocalBuild,
  );

  testWidgets(
    'normal app keeps jobs card non-navigable and never resolves detail',
    (tester) async {
      final streams = _ContentStreams();
      var resolverCalls = 0;
      final detailsRepository = PublicJobDetailsRepository(
        resolveJob: (_) async {
          resolverCalls++;
          return const PublicJob(id: 'job-normal', title: 'Vaga normal');
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LocalJobsView(
            streamFactory: streams.create,
            jobDetailsRepository: detailsRepository,
          ),
        ),
      );
      streams.controllers.single.add(
        _snapshotWithIds([
          (id: 'job-normal', data: {'title': 'Vaga normal', 'published': true}),
        ]),
      );
      await tester.pump();

      expect(find.text('Ver vaga'), findsNothing);
      await tester.tap(find.text('Vaga normal'));
      await tester.pumpAndSettle();
      expect(find.byType(JobDetailPage), findsNothing);
      expect(resolverCalls, 0);
    },
    skip: isLocalBuild,
  );

  testWidgets('other collection cards preserve their existing link action', (
    tester,
  ) async {
    final streams = _ContentStreams();
    await tester.pumpWidget(_app(streams: streams, collection: 'news'));
    streams.controllers.single.add(
      _snapshot([
        {
          'title': 'Notícia com link público',
          'published': true,
          'link': 'https://example.com/noticia',
        },
      ]),
    );
    await tester.pump();

    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('Ver vaga'), findsNothing);
    expect(find.byType(JobDetailPage), findsNothing);
  });

  testWidgets(
    'demo keeps the existing external-link action for other content',
    (tester) async {
      final streams = _ContentStreams();
      await tester.pumpWidget(_app(streams: streams, collection: 'news'));
      streams.controllers.single.add(
        _snapshot([
          {
            'title': 'Notícia com link público',
            'published': true,
            'link': 'https://example.com/noticia',
          },
        ]),
      );
      await tester.pump();
      await tester.tap(find.text('Abrir'));
      await tester.pump();

      expect(
        find.text('Links externos indisponíveis no ambiente local.'),
        findsOneWidget,
      );
    },
    skip: !isLocalBuild,
  );
}
