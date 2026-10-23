import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/admin_job_repository.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

class _Jobs implements AdminJobRepository {
  final requests = <({String? cursor, Completer<AdminJobPage> result})>[];
  final reads = <String>[];
  @override
  Future<AdminJobPage> list({int pageSize = 30, String? cursor}) {
    final result = Completer<AdminJobPage>();
    requests.add((cursor: cursor, result: result));
    return result.future;
  }

  @override
  Future<AdminJobRecord> get(String jobId) async {
    reads.add(jobId);
    return AdminJobRecord(
      jobId: jobId,
      publicData: {'title': 'Detalhe autorizado'},
      privateData: {},
    );
  }

  @override
  String reserveCreateId() => 'new-id';
  @override
  Future<String> create({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  }) async => jobId;
  @override
  Future<void> update({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  }) async {}
  @override
  Future<void> delete(String jobId) async {}
}

AdminJobSummary _job(String id, String title) =>
    AdminJobSummary(id: id, title: title, published: true, active: true);

Widget _app(
  _Jobs jobs, {
  String collection = 'jobs',
  Stream<QuerySnapshot<Map<String, dynamic>>> Function()? stream,
}) => MaterialApp(
  home: ContentManager(
    collection: collection,
    title: 'Gerenciar',
    jobRepository: jobs,
    itemsStreamFactory: stream,
  ),
);

// Offline snapshots exercise the unchanged non-job StreamBuilder path.
// ignore: subtype_of_sealed_class
class _Snapshot implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Document implements QueryDocumentSnapshot<Map<String, dynamic>> {
  @override
  Map<String, dynamic> data() => {
    'title': 'Evento do stream',
    'published': false,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('jobs load once on rebuild without creating a Firestore stream', (
    tester,
  ) async {
    final jobs = _Jobs();
    var streamCalls = 0;
    Stream<QuerySnapshot<Map<String, dynamic>>> stream() {
      streamCalls++;
      throw StateError('jobs must not subscribe');
    }

    await tester.pumpWidget(_app(jobs, stream: stream));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(jobs.requests, hasLength(1));
    await tester.pumpWidget(_app(jobs, stream: stream));
    expect(jobs.requests, hasLength(1));
    expect(streamCalls, 0);
    jobs.requests.single.result.complete(AdminJobPage(items: []));
    await tester.pumpAndSettle();
    expect(
      find.text('Ainda não há itens. Use Adicionar para publicar.'),
      findsOneWidget,
    );
  });

  testWidgets('jobs show a sanitized error and retry the first page', (
    tester,
  ) async {
    final jobs = _Jobs();
    await tester.pumpWidget(_app(jobs));
    jobs.requests.single.result.completeError(
      StateError('private backend detail'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar os itens.'), findsOneWidget);
    expect(find.textContaining('private backend detail'), findsNothing);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(jobs.requests, hasLength(2));
    expect(jobs.requests.last.cursor, isNull);
    jobs.requests.last.result.complete(
      AdminJobPage(items: [_job('a', 'Recuperada')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recuperada'), findsOneWidget);
  });

  testWidgets(
    'load more preserves repository order and suppresses duplicates',
    (tester) async {
      final jobs = _Jobs();
      await tester.pumpWidget(_app(jobs));
      jobs.requests.single.result.complete(
        AdminJobPage(
          items: [_job('z', 'Z primeiro'), _job('a', 'A segundo')],
          nextCursor: 'page-2',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Z primeiro')).dy,
        lessThan(tester.getTopLeft(find.text('A segundo')).dy),
      );
      await tester.tap(find.text('Carregar mais'));
      await tester.pump();
      expect(jobs.requests.last.cursor, 'page-2');
      await tester.pumpWidget(_app(jobs));
      expect(jobs.requests, hasLength(2));
      jobs.requests.last.result.complete(
        AdminJobPage(
          items: [_job('a', 'A duplicado'), _job('m', 'M terceiro')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A duplicado'), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(
        tester.getTopLeft(find.text('A segundo')).dy,
        lessThan(tester.getTopLeft(find.text('M terceiro')).dy),
      );
      expect(find.text('Carregar mais'), findsNothing);
    },
  );

  testWidgets('load more failure keeps items and retries the same cursor', (
    tester,
  ) async {
    final jobs = _Jobs();
    await tester.pumpWidget(_app(jobs));
    jobs.requests.single.result.complete(
      AdminJobPage(items: [_job('a', 'Mantida')], nextCursor: 'next'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carregar mais'));
    jobs.requests.last.result.completeError(AdminJobException('unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Mantida'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(jobs.requests.last.cursor, 'next');
    jobs.requests.last.result.complete(
      AdminJobPage(items: [_job('b', 'Segunda')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Segunda'), findsOneWidget);
  });

  testWidgets(
    'selected job loads its real ID and reloads first page on return',
    (tester) async {
      final jobs = _Jobs();
      await tester.pumpWidget(_app(jobs));
      jobs.requests.single.result.complete(
        AdminJobPage(items: [_job('real-job-id', 'Resumo antigo')]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resumo antigo'));
      await tester.pumpAndSettle();
      expect(jobs.reads, ['real-job-id']);
      final editor = tester.widget<ContentEditor>(find.byType(ContentEditor));
      expect(editor.doc, isNull);
      expect(editor.jobId, 'real-job-id');
      expect(editor.jobSummary!.title, 'Resumo antigo');
      expect(find.text('Detalhe autorizado'), findsOneWidget);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(jobs.requests, hasLength(2));
      expect(jobs.requests.last.cursor, isNull);
      jobs.requests.last.result.complete(
        AdminJobPage(items: [_job('new', 'Página atualizada')]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Página atualizada'), findsOneWidget);
      expect(find.text('Resumo antigo'), findsNothing);
    },
  );

  testWidgets('return from adding a job reloads the first page', (
    tester,
  ) async {
    final jobs = _Jobs();
    await tester.pumpWidget(_app(jobs));
    jobs.requests.single.result.complete(AdminJobPage(items: []));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    final editor = tester.widget<ContentEditor>(find.byType(ContentEditor));
    expect(editor.jobRepository, same(jobs));
    expect(editor.jobId, isNull);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(jobs.requests, hasLength(2));
    jobs.requests.last.result.complete(AdminJobPage(items: []));
    await tester.pumpAndSettle();
  });

  testWidgets('non-jobs retain their existing stream and item styles', (
    tester,
  ) async {
    final jobs = _Jobs();
    final stream = StreamController<QuerySnapshot<Map<String, dynamic>>>();
    addTearDown(stream.close);
    var subscriptions = 0;
    await tester.pumpWidget(
      _app(
        jobs,
        collection: 'events',
        stream: () {
          subscriptions++;
          return stream.stream;
        },
      ),
    );
    expect(jobs.requests, isEmpty);
    expect(subscriptions, 1);
    expect(find.text('Carregando itens…'), findsOneWidget);
    stream.add(_Snapshot([_Document()]));
    await tester.pumpAndSettle();
    expect(find.text('Evento do stream'), findsOneWidget);
    expect(find.text('Rascunho'), findsOneWidget);
    expect(find.text('Carregar mais'), findsNothing);
  });
}
