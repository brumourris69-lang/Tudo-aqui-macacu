import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/beta_environment.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/admin_job_repository.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_hero_media.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_hours.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'support/fake_spark_admin_content_operations.dart';

const _a = 'https://example.com/a.jpg';
const _b = 'https://example.com/b.jpg';
const _c = 'https://example.com/c.jpg';

// Offline document double for the actual editor.
// ignore: subtype_of_sealed_class
class _Document implements DocumentSnapshot<Map<String, dynamic>> {
  _Document(this.reference, this.fields);
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  @override
  String get id => 'doc-id';
  final Map<String, dynamic> fields;
  @override
  Map<String, dynamic> data() => Map<String, dynamic>.from(fields);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _JobRepository implements AdminJobRepository {
  _JobRepository({
    Map<String, dynamic>? publicData,
    this.privateData,
    this.readError,
    this.writeError,
    this.pendingRead,
    this.pendingWrite,
  }) : publicData = publicData ?? const {'title': 'Vaga atual'};
  Map<String, dynamic>? privateData;
  Map<String, dynamic> publicData;
  Object? readError;
  Object? writeError;
  Completer<AdminJobRecord>? pendingRead;
  Completer<void>? pendingWrite;
  Map<String, dynamic>? createdPublic;
  Map<String, dynamic>? createdPrivate;
  Map<String, dynamic>? updatedPublic;
  Map<String, dynamic>? updatedPrivate;
  String? updatedId;
  String? deletedId;
  final createIds = <String>[];
  int reserves = 0;
  String? pendingCreateId;
  int creates = 0;
  int updates = 0;
  int deletes = 0;

  @override
  Future<AdminJobPage> list({int pageSize = 30, String? cursor}) async =>
      AdminJobPage(items: []);

  @override
  Future<AdminJobRecord> get(String jobId) async {
    if (readError case final error?) throw error;
    if (pendingRead != null) return pendingRead!.future;
    return AdminJobRecord(
      jobId: jobId,
      publicData: publicData,
      privateData: privateData ?? {},
    );
  }

  @override
  String reserveCreateId() {
    return pendingCreateId ??= 'reserved-job-${++reserves}';
  }

  @override
  Future<String> create({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  }) async {
    createIds.add(jobId);
    if (pendingWrite != null) await pendingWrite!.future;
    if (writeError case final error?) {
      if (error is AdminJobException && error.createReservationReleased) {
        pendingCreateId = null;
      }
      throw error;
    }
    creates++;
    createdPublic = Map.of(publicData);
    createdPrivate = Map.of(privateData);
    pendingCreateId = null;
    return jobId;
  }

  @override
  Future<void> update({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  }) async {
    if (pendingWrite != null) await pendingWrite!.future;
    if (writeError case final error?) throw error;
    updates++;
    updatedId = jobId;
    updatedPublic = Map.of(publicData);
    updatedPrivate = Map.of(privateData);
  }

  @override
  Future<void> delete(String jobId) async {
    if (pendingWrite != null) await pendingWrite!.future;
    if (writeError case final error?) throw error;
    deletes++;
    deletedId = jobId;
  }
}

// Model only Firestore's top-level update/delete contract, intercepting the
// actual write before audit/navigation. A replacement set is not supported.
// ignore: subtype_of_sealed_class
class _Reference implements DocumentReference<Map<String, dynamic>> {
  _Reference(Map<String, dynamic> initial)
    : stored = Map<String, dynamic>.from(initial);
  final Map<String, dynamic> stored;
  final List<Map<String, dynamic>> writes = [];
  @override
  Future<void> update(Map<Object, Object?> data) async {
    final patch = Map<String, dynamic>.from(data);
    writes.add(patch);
    for (final entry in patch.entries) {
      if (entry.value == FieldValue.delete()) {
        stored.remove(entry.key);
      } else {
        stored[entry.key] = entry.value;
      }
    }
    throw FirebaseException(plugin: 'test', code: 'intercepted-write');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<dynamic> _mount(
  WidgetTester tester, {
  Size size = const Size(1000, 5000),
  _Reference? reference,
  Map<String, dynamic>? initial,
  String collection = 'news',
  AdminJobRepository? jobRepository,
  FakeSparkAdminContentOperations? sparkContentOperations,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ContentEditor(
        collection: collection,
        doc: collection == 'jobs' || reference == null
            ? null
            : _Document(reference, initial!),
        jobId: collection == 'jobs' && reference != null ? 'doc-id' : null,
        jobRepository: jobRepository,
        sparkContentOperations:
            sparkContentOperations ??
            FakeSparkAdminContentOperations(
              onSave:
                  ({
                    required collection,
                    required id,
                    required data,
                    privateJobData,
                  }) async {
                    if (reference == null) return;
                    try {
                      await reference.update(data);
                    } on FirebaseException catch (error) {
                      if (error.code != 'intercepted-write') rethrow;
                    }
                  },
            ),
        auditRecorder:
            ({
              required action,
              required collection,
              required documentId,
              label,
            }) async {},
      ),
    ),
  );
  return tester.state(find.byType(ContentEditor));
}

Map<String, dynamic> _initial() => {
  'title': 'Evento',
  'description': 'Descrição antiga',
  'imageUrl': _a,
  'galleryUrls': [_a, _b, _c],
  'legacyField': 'preservar',
  'metadata': {
    'source': 'import',
    'extra': ['original'],
  },
};

Future<void> _save(WidgetTester tester, dynamic editor) async {
  await editor.save();
  await tester.pump();
  expect(tester.takeException(), isNull);
}

ContentMediaGalleryEditor _gallery(WidgetTester tester) => tester
    .widget<ContentMediaGalleryEditor>(find.byType(ContentMediaGalleryEditor));

Future<void> _selectBusinessStep(WidgetTester tester, int step) async {
  await tester.tap(find.byKey(ValueKey('establishment-step-$step')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('establishment icon picker keeps one named icon selection', (
    tester,
  ) async {
    final dynamic editor = await _mount(tester, collection: 'establishments');

    expect(find.byType(NamedVisualIconPicker), findsOneWidget);
    expect(find.byType(VisualIconPicker), findsNothing);

    for (final step in [1, 2, 3]) {
      await _selectBusinessStep(tester, step);
      expect(
        find.byType(NamedVisualIconPicker),
        findsNothing,
        reason: 'o seletor de ícones não deve aparecer na etapa ${step + 1}',
      );
    }

    await _selectBusinessStep(tester, 0);
    expect(find.byType(NamedVisualIconPicker), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('named-home-icon-cachoeiras')));
    await tester.pump();

    final picker = tester.widget<NamedVisualIconPicker>(
      find.byType(NamedVisualIconPicker),
    );
    expect(picker.value, 'cachoeiras');
    expect(editor.prepareSaveData()['iconKey'], 'cachoeiras');
  });

  testWidgets('establishment media step uses compact link-only logo controls', (
    tester,
  ) async {
    final dynamic editor = await _mount(tester, collection: 'establishments');
    await _selectBusinessStep(tester, 2);

    expect(find.text('Logo da empresa (800 × 800 px)'), findsOneWidget);
    expect(find.byType(CloudinaryUploadHelper), findsNothing);
    expect(
      find.textContaining('Envie uma imagem quadrada de 800'),
      findsNothing,
    );
    expect(find.text('Capa e galeria'), findsOneWidget);
    expect(find.text('Vídeos (YouTube ou Vimeo)'), findsOneWidget);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller == editor.galleryInput,
      ),
      'https://res.cloudinary.com/demo/image/upload/test.jpg',
    );
    await tester.tap(find.text('Adicionar à galeria'));
    await tester.pump();
    expect(editor.galleryItems, hasLength(1));
    expect(editor.galleryItems.single, endsWith('/test.jpg'));
  });

  testWidgets('adding gallery photos explains empty and duplicate links', (
    tester,
  ) async {
    final dynamic editor = await _mount(tester, collection: 'establishments');
    await _selectBusinessStep(tester, 2);

    await tester.tap(find.text('Adicionar à galeria'));
    await tester.pump();
    expect(
      find.text('Cole pelo menos um link HTTPS de imagem antes de adicionar.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller == editor.galleryInput,
      ),
      'https://res.cloudinary.com/demo/image/upload/foto.jpg',
    );
    await tester.tap(find.text('Adicionar à galeria'));
    await tester.pump();
    expect(editor.galleryItems, hasLength(1));

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller == editor.galleryInput,
      ),
      'https://res.cloudinary.com/demo/image/upload/foto.jpg',
    );
    await tester.tap(find.text('Adicionar à galeria'));
    await tester.pump();
    expect(find.text('Esses links já estão na galeria.'), findsOneWidget);
    expect(editor.galleryItems, hasLength(1));
  });

  testWidgets('new city events are drafts and expose event-specific fields', (
    tester,
  ) async {
    final dynamic editor = await _mount(tester, collection: 'events');
    final saveData = editor.prepareSaveData() as Map<String, dynamic>;

    expect(saveData['published'], isFalse);
    expect(saveData['active'], isTrue);
    expect(saveData['deleted'], isFalse);
    for (final label in [
      'Data do evento',
      'Último dia (opcional)',
      'Horário de início (opcional)',
      'Horário de término (opcional)',
      'Organizador (opcional)',
      'Inscrição (link HTTPS, opcional)',
      'Contato público (link HTTPS, opcional)',
      'Link do Google Maps',
    ]) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        ),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.text('Contato administrativo (privado)'), findsNothing);
  });

  testWidgets('event payload keeps schedule and public destination fields', (
    tester,
  ) async {
    final dynamic editor = await _mount(tester, collection: 'events');
    editor.title.text = 'Festival de teste';
    editor.category.text = 'Cultura';
    editor.eventDate.text = '2030-12-31';
    editor.eventEndDate.text = '2031-01-02';
    editor.eventStartTime.text = '19:30';
    editor.eventEndTime.text = '22:00';
    editor.eventOrganizer.text = 'Organização fictícia';
    editor.eventRegistrationUrl.text =
        'https://events.example.invalid/inscricao';
    editor.eventContactUrl.text = 'https://events.example.invalid/contato';
    editor.location.text = 'Praça de teste';
    editor.maps.text = 'https://maps.example.invalid/evento';

    final data = editor.prepareSaveData() as Map<String, dynamic>;
    expect(data['eventDate'], '2030-12-31');
    expect(data['endDate'], '2031-01-02');
    expect(data['startTime'], '19:30');
    expect(data['endTime'], '22:00');
    expect(data['organizer'], 'Organização fictícia');
    expect(data['registrationUrl'], 'https://events.example.invalid/inscricao');
    expect(data['contactUrl'], 'https://events.example.invalid/contato');
    expect(data['location'], 'Praça de teste');
    expect(data['maps'], 'https://maps.example.invalid/evento');
    expect(data['published'], isFalse);
  });

  testWidgets('event editor blocks missing date without losing entered data', (
    tester,
  ) async {
    final dynamic editor = await _mount(tester, collection: 'events');
    editor.title.text = 'Festival fictício';
    editor.category.text = 'Cultura';

    await editor.save();
    await tester.pump();

    expect(editor.title.text, 'Festival fictício');
    expect(editor.category.text, 'Cultura');
    expect(
      find.text('Informe título, categoria, data e horários válidos (HH:mm).'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('new establishments start as drafts until explicitly published', (
    tester,
  ) async {
    final dynamic editor = await _mount(tester, collection: 'establishments');

    expect(
      (editor.prepareSaveData() as Map<String, dynamic>)['published'],
      isFalse,
    );
    expect(find.text('1 Dados'), findsOneWidget);
    expect(find.text('2 Contato'), findsOneWidget);
    expect(find.text('3 Fotos'), findsOneWidget);
    expect(find.text('4 Detalhes e publicação'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('establishment-step-2')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('establishment-step-2')),
          )
          .selected,
      isTrue,
    );
    expect(find.text('Título ou nome'), findsNothing);
    expect(find.byType(ContentMediaGalleryEditor), findsOneWidget);
    expect(find.text('Publicado'), findsNothing);
    expect(find.text('Etapa 3 de 4'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('establishment-step-back')));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller == editor.whatsapp,
      ),
      findsOneWidget,
    );
    expect(find.text('Contato administrativo (privado)'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('establishment-step-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('establishment-step-next')));
    await tester.pumpAndSettle();
    expect(find.text('Publicado'), findsOneWidget);
    expect(find.text('Salvar estabelecimento'), findsOneWidget);
  });

  testWidgets(
    'business hours selections are saved in the existing hours field',
    (tester) async {
      final dynamic editor = await _mount(tester, collection: 'establishments');
      await _selectBusinessStep(tester, 3);

      final picker = tester.widget<BusinessHoursEditor>(
        find.byType(BusinessHoursEditor),
      );
      picker.onChanged(
        'Seg–Sex: 09:00 às 18:00; Sáb: Fechado; Dom: Não informado',
      );

      expect(
        (editor.prepareSaveData() as Map<String, dynamic>)['hours'],
        'Seg–Sex: 09:00 às 18:00; Sáb: Fechado; Dom: Não informado',
      );
    },
  );

  testWidgets('establishment editor fits final controls on a small phone', (
    tester,
  ) async {
    await _mount(
      tester,
      collection: 'establishments',
      size: const Size(360, 640),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('establishment-step-3')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('content-editor-save'));
    expect(saveButton, findsOneWidget);
    expect(tester.getRect(saveButton).right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'establishment requires a category without clearing entered data',
    (tester) async {
      final dynamic editor = await _mount(tester, collection: 'establishments');
      editor.title.text = 'Mercearia fictícia';

      await editor.save();
      await tester.pump();

      expect(editor.title.text, 'Mercearia fictícia');
      expect(editor.category.text, isEmpty);
      expect(
        find.text('Escolha uma categoria para continuar.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('establishment requires a name and keeps the selected category', (
    tester,
  ) async {
    final initial = {'name': 'Nome existente', 'category': 'Comércio'};
    final dynamic editor = await _mount(
      tester,
      reference: _Reference(initial),
      initial: initial,
      collection: 'establishments',
    );
    editor.title.clear();

    await editor.save();
    await tester.pump();

    expect(editor.title.text, isEmpty);
    expect(editor.category.text, 'Comércio');
    expect(find.text('Informe o nome do estabelecimento.'), findsOneWidget);
  });

  testWidgets('legacy save is blocked for an outbox-managed establishment', (
    tester,
  ) async {
    final initial = _initial()
      ..addAll({
        'catalogVersion': 1,
        'outboxOperationId': '00000000-0000-4000-8000-000000000001',
      });
    final reference = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      collection: 'establishments',
      reference: reference,
      initial: initial,
    );

    editor.title.text = 'Alteração que não deve gravar';
    await editor.save();
    await tester.pump();

    expect(reference.writes, isEmpty);
    expect(find.textContaining('já usa a outbox'), findsOneWidget);
  });

  testWidgets(
    'physical delete is blocked for an outbox-managed establishment',
    (tester) async {
      final initial = _initial()
        ..addAll({
          'catalogVersion': 1,
          'outboxOperationId': '00000000-0000-4000-8000-000000000001',
        });
      final reference = _Reference(initial);
      final dynamic editor = await _mount(
        tester,
        collection: 'establishments',
        reference: reference,
        initial: initial,
      );

      await editor.remove();
      await tester.pump();

      expect(reference.writes, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.textContaining('não pode ser excluído fisicamente'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'job waits for authorized current detail before enabling editing',
    (tester) async {
      final pending = Completer<AdminJobRecord>();
      final repository = _JobRepository(pendingRead: pending);
      final dynamic editor = await _mount(
        tester,
        collection: 'jobs',
        reference: _Reference({}),
        initial: {},
        jobRepository: repository,
      );
      final titleField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller == editor.title,
      );
      expect(tester.widget<TextField>(titleField).enabled, isFalse);
      await editor.save();
      expect(repository.updates, 0);
      pending.complete(
        AdminJobRecord(
          jobId: 'doc-id',
          publicData: {
            'title': 'Título atual autorizado',
            'description': 'Descrição atual',
            'published': false,
            'expiresAt': '2030-02-03T02:59:59.000Z',
          },
          privateData: {'contact': 'atual@example.invalid'},
        ),
      );
      await tester.pumpAndSettle();
      expect(editor.title.text, 'Título atual autorizado');
      expect(editor.description.text, 'Descrição atual');
      expect(editor.published, isFalse);
      expect(editor.contact.text, 'atual@example.invalid');
      expect(tester.widget<TextField>(titleField).enabled, isTrue);
    },
  );

  testWidgets(
    'unchanged private fields are omitted and explicit clears are patches',
    (tester) async {
      final repository = _JobRepository(
        privateData: {
          'contact': 'preserve@example.invalid',
          'maps': 'https://one.invalid',
          'mapsUrl': 'https://two.invalid',
        },
      );
      final dynamic editor = await _mount(
        tester,
        collection: 'jobs',
        reference: _Reference({}),
        initial: {},
        jobRepository: repository,
      );
      await tester.pumpAndSettle();
      editor.description.text = 'Atualização pública';
      await _save(tester, editor);
      expect(repository.updatedPrivate, isEmpty);
    },
  );

  testWidgets('job payload uses UTC expiry and no Firestore sentinels', (
    tester,
  ) async {
    final repository = _JobRepository();
    final dynamic editor = await _mount(
      tester,
      collection: 'jobs',
      jobRepository: repository,
    );
    editor.title.text = 'Nova vaga';
    editor.expires.text = '2030-02-03';
    await _save(tester, editor);
    expect(repository.createdPublic!.containsKey('updatedAt'), isFalse);
    expect(
      repository.createdPublic!['expiresAt'],
      DateTime(2030, 2, 3, 23, 59, 59).toUtc().toIso8601String(),
    );
  });

  testWidgets(
    'Spark Beta create, edit, publish, and unpublish use only the job repository',
    (tester) async {
      final repository = _JobRepository();
      final sparkOperations = FakeSparkAdminContentOperations();
      final dynamic createEditor = await _mount(
        tester,
        collection: 'jobs',
        jobRepository: repository,
        sparkContentOperations: sparkOperations,
      );
      createEditor.title.text = 'Vaga sintética Beta';
      createEditor.published = false;
      await _save(tester, createEditor);

      expect(repository.creates, 1);
      expect(repository.createdPublic!['published'], isFalse);
      expect(sparkOperations.saves, isEmpty);
      expect(sparkOperations.reservedCollections, isEmpty);

      await tester.pumpWidget(const SizedBox());
      repository.publicData = Map<String, dynamic>.from(
        repository.createdPublic!,
      );
      final dynamic editEditor = await _mount(
        tester,
        collection: 'jobs',
        reference: _Reference({}),
        initial: {},
        jobRepository: repository,
        sparkContentOperations: sparkOperations,
      );
      await tester.pumpAndSettle();
      editEditor.title.text = 'Vaga sintética editada';
      editEditor.published = true;
      await _save(tester, editEditor);

      expect(repository.updates, 1);
      expect(repository.updatedPublic!['title'], 'Vaga sintética editada');
      expect(repository.updatedPublic!['published'], isTrue);

      await tester.pumpWidget(const SizedBox());
      repository.publicData = Map<String, dynamic>.from(
        repository.updatedPublic!,
      );
      final dynamic unpublishEditor = await _mount(
        tester,
        collection: 'jobs',
        reference: _Reference({}),
        initial: {},
        jobRepository: repository,
        sparkContentOperations: sparkOperations,
      );
      await tester.pumpAndSettle();
      unpublishEditor.published = false;
      await _save(tester, unpublishEditor);

      expect(repository.updates, 2);
      expect(repository.updatedPublic!['published'], isFalse);
      expect(sparkOperations.saves, isEmpty);
      expect(sparkOperations.deletions, isEmpty);

      await tester.pumpWidget(const SizedBox());
      final dynamic deleteEditor = await _mount(
        tester,
        collection: 'jobs',
        reference: _Reference({}),
        initial: {},
        jobRepository: repository,
        sparkContentOperations: sparkOperations,
      );
      await tester.pumpAndSettle();
      final deletion = deleteEditor.remove() as Future<void>;
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
      await deletion;

      expect(repository.deletes, 1);
      expect(repository.deletedId, 'doc-id');
      expect(sparkOperations.saves, isEmpty);
      expect(sparkOperations.deletions, isEmpty);
    },
    skip: !BetaEnvironment.enabled,
  );

  testWidgets(
    'job create waits for acknowledgement and retries the reserved ID',
    (tester) async {
      final pending = Completer<void>();
      final repository = _JobRepository(
        pendingWrite: pending,
        writeError: AdminJobException('unavailable'),
      );
      final dynamic editor = await _mount(
        tester,
        collection: 'jobs',
        jobRepository: repository,
      );
      editor.title.text = 'Nova vaga';
      final save = editor.save() as Future<void>;
      await tester.pump();
      expect(editor.saving, isTrue);
      expect(repository.creates, 0);
      expect(find.byType(ContentEditor), findsOneWidget);
      pending.complete();
      await save;
      await tester.pump();
      repository.pendingWrite = null;
      repository.writeError = null;
      await _save(tester, editor);
      expect(repository.createIds, ['reserved-job-1', 'reserved-job-1']);
      expect(repository.reserves, 1);
      expect(repository.creates, 1);
    },
  );

  testWidgets('job create reserves a fresh ID after a definitive rejection', (
    tester,
  ) async {
    final repository = _JobRepository(
      writeError: AdminJobException(
        'failed-precondition',
        createReservationReleased: true,
      ),
    );
    final dynamic editor = await _mount(
      tester,
      collection: 'jobs',
      jobRepository: repository,
    );
    editor.title.text = 'Nova vaga';

    await _save(tester, editor);
    expect(repository.createIds, ['reserved-job-1']);
    expect(repository.creates, 0);

    repository.writeError = null;
    await _save(tester, editor);

    expect(repository.createIds, ['reserved-job-1', 'reserved-job-2']);
    expect(repository.creates, 1);
    expect(repository.reserves, 2);
  });

  testWidgets(
    'job create keeps an ambiguous reservation when payloads conflict',
    (tester) async {
      final repository = _JobRepository(
        writeError: AdminJobException(
          'failed-precondition',
          createPayloadConflict: true,
        ),
      );
      final dynamic editor = await _mount(
        tester,
        collection: 'jobs',
        jobRepository: repository,
      );
      editor.title.text = 'Nova vaga';

      await _save(tester, editor);
      expect(repository.createIds, ['reserved-job-1']);
      expect(repository.reserves, 1);
      expect(
        find.textContaining('bloqueado para evitar duplicação.'),
        findsOneWidget,
      );

      await _save(tester, editor);

      expect(repository.createIds, ['reserved-job-1', 'reserved-job-1']);
      expect(repository.reserves, 1);
      expect(repository.creates, 0);
    },
  );

  testWidgets('job delete waits for acknowledgement and reports failure', (
    tester,
  ) async {
    final pending = Completer<void>();
    final repository = _JobRepository(
      pendingWrite: pending,
      writeError: AdminJobException('unavailable'),
    );
    final dynamic editor = await _mount(
      tester,
      collection: 'jobs',
      reference: _Reference({}),
      initial: {},
      jobRepository: repository,
    );
    await tester.pumpAndSettle();
    if (BetaEnvironment.enabled) {
      final deletion = editor.remove() as Future<void>;
      await tester.pumpAndSettle();
      expect(find.text('Excluir conteúdo?'), findsOneWidget);
      expect(repository.deletes, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await deletion;
      expect(repository.deletes, 0);
      return;
    }

    final deletion = editor.remove() as Future<void>;
    await tester.pump();
    expect(find.byType(ContentEditor), findsOneWidget);
    expect(repository.deletes, 0);
    pending.complete();
    await deletion;
    await tester.pump();
    expect(
      find.text('Não foi possível excluir agora. Tente novamente.'),
      findsOneWidget,
    );
    repository.pendingWrite = null;
    repository.writeError = null;
    await editor.remove();
    expect(repository.deletedId, 'doc-id');
  });

  testWidgets('Tecnologia is selectable for new and existing businesses', (
    tester,
  ) async {
    for (final editing in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      final initial = <String, dynamic>{
        'title': 'Fixture',
        'category': 'Tecnologia',
        'subcategory': 'Provedores de internet',
        'imageUrl': '',
      };
      final dynamic editor = await _mount(
        tester,
        reference: editing ? _Reference(initial) : null,
        initial: editing ? initial : null,
        collection: 'establishments',
      );
      final selector = tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .first;
      final dropdown = tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .first;
      expect(dropdown.items!.any((item) => item.value == 'Tecnologia'), isTrue);
      if (editing) {
        expect(editor.category.text, 'Tecnologia');
        expect(editor.subcategory.text, 'Provedores de internet');
      }
      selector.onChanged!('Tecnologia');
      await tester.pump();
      final data = editor.prepareSaveData() as Map<String, dynamic>;
      expect(data['category'], 'Tecnologia');
      expect(data['artwork'], 18);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'ad editor preserves media and link and saves order and activation',
    (tester) async {
      final initial = <String, dynamic>{
        'title': 'Campanha',
        'imageUrl': _a,
        'link': 'https://example.com',
        'order': 12,
        'active': false,
        'legacyField': 'preservar',
      };
      final ref = _Reference(initial);
      final dynamic editor = await _mount(
        tester,
        reference: ref,
        initial: initial,
        collection: 'ads',
      );
      expect(editor.bannerOrder.text, '12');
      expect(editor.bannerActive, isFalse);
      expect(find.text('Link direto da imagem (HTTPS)'), findsOneWidget);
      expect(
        find.text('Página que abre ao tocar no anúncio (HTTPS)'),
        findsOneWidget,
      );
      expect(find.byType(CloudinaryUploadHelper), findsNothing);
      editor.bannerOrder.text = '3';
      editor.bannerActive = true;
      await _save(tester, editor);
      expect(ref.stored['order'], 3);
      expect(ref.stored['active'], isTrue);
      expect(ref.stored['link'], initial['link']);
      expect(ref.stored['imageUrl'], initial['imageUrl']);
      expect(ref.stored['legacyField'], 'preservar');
    },
  );

  testWidgets('ad editor requires direct HTTPS image and page URLs', (
    tester,
  ) async {
    final initial = <String, dynamic>{
      'title': 'Campanha',
      'imageUrl': _a,
      'link': 'https://example.com/destino',
    };
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
      collection: 'ads',
    );

    editor.imageUrl.text = '';
    await _save(tester, editor);
    expect(ref.writes, isEmpty);
    expect(
      find.text(
        'Informe o link HTTPS direto da imagem e a página HTTPS que será aberta ao tocar no anúncio.',
      ),
      findsOneWidget,
    );

    editor.imageUrl.text = 'http://example.com/banner.jpg';
    await _save(tester, editor);
    expect(ref.writes, isEmpty);

    editor.imageUrl.text = _a;
    editor.link.text = 'javascript:alert(1)';
    await _save(tester, editor);
    expect(ref.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'establishment editor saves active status and preserves legacy fields',
    (tester) async {
      final initial = <String, dynamic>{
        'title': 'Comércio de teste',
        'active': true,
        'legacyField': 'preservar',
      };
      final ref = _Reference(initial);
      final dynamic editor = await _mount(
        tester,
        reference: ref,
        initial: initial,
        collection: 'establishments',
      );

      await _selectBusinessStep(tester, 3);
      await tester.tap(find.text('Estabelecimento ativo'));
      await tester.pump();
      final data = Map<String, dynamic>.from(editor.prepareSaveData());
      expect(data['active'], isFalse);
      await _save(tester, editor);
      expect(ref.stored['active'], isFalse);
      expect(ref.stored['legacyField'], 'preservar');
    },
  );

  testWidgets(
    'public contact approval defaults off for new and legacy businesses',
    (tester) async {
      final dynamic newEditor = await _mount(
        tester,
        collection: 'establishments',
      );
      expect(newEditor.publicContactApproved, isFalse);
      expect(
        (newEditor.prepareSaveData()
            as Map<String, dynamic>)['publicContactApproved'],
        isFalse,
      );

      await tester.pumpWidget(const SizedBox());
      final initial = {
        'title': 'Comércio legado',
        'phone': '22221000',
        'whatsapp': '22221000',
      };
      final ref = _Reference(initial);
      final dynamic legacyEditor = await _mount(
        tester,
        reference: ref,
        initial: initial,
        collection: 'establishments',
      );
      expect(legacyEditor.publicContactApproved, isFalse);
      await _save(tester, legacyEditor);

      expect(ref.stored['publicContactApproved'], isFalse);
      expect(ref.stored['phone'], '22221000');
      expect(ref.stored['whatsapp'], '22221000');
    },
  );

  testWidgets(
    'business contact approval can be enabled and disabled without deleting contacts',
    (tester) async {
      final initial = {
        'title': 'Comércio cadastrado',
        'phone': '22221000',
        'whatsapp': '22221000',
        'publicContactApproved': false,
      };
      final ref = _Reference(initial);
      dynamic editor = await _mount(
        tester,
        reference: ref,
        initial: initial,
        collection: 'establishments',
      );

      await _selectBusinessStep(tester, 3);
      await tester.tap(find.text('Permitir exibição pública dos contatos'));
      await tester.pump();
      await _save(tester, editor);
      expect(ref.stored['publicContactApproved'], isTrue);
      expect(ref.stored['phone'], '22221000');
      expect(ref.stored['whatsapp'], '22221000');

      await tester.pumpWidget(const SizedBox());
      final updated = Map<String, dynamic>.from(ref.stored);
      editor = await _mount(
        tester,
        reference: ref,
        initial: updated,
        collection: 'establishments',
      );
      await _selectBusinessStep(tester, 3);
      await tester.tap(find.text('Permitir exibição pública dos contatos'));
      await tester.pump();
      await _save(tester, editor);

      expect(ref.stored['publicContactApproved'], isFalse);
      expect(ref.stored['phone'], '22221000');
      expect(ref.stored['whatsapp'], '22221000');
    },
  );

  testWidgets(
    'contact approval is not persisted for other content collections',
    (tester) async {
      for (final collection in ['events', 'jobs', 'routes', 'utilities']) {
        await tester.pumpWidget(const SizedBox());
        final dynamic editor = await _mount(
          tester,
          collection: collection,
          jobRepository: collection == 'jobs' ? _JobRepository() : null,
        );
        expect(
          (editor.prepareSaveData() as Map<String, dynamic>).containsKey(
            'publicContactApproved',
          ),
          isFalse,
        );
      }
    },
  );

  testWidgets('establishment editor rejects unsafe external destinations', (
    tester,
  ) async {
    final initial = {'title': 'Comércio de teste'};
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
      collection: 'establishments',
    );
    editor.link.text = 'javascript:alert(1)';

    await editor.save();
    await tester.pump();

    expect(ref.writes, isEmpty);
    expect(find.textContaining('URL HTTPS válida'), findsOneWidget);
  });

  testWidgets(
    'establishment contacts reject malformed values and spoofed hosts',
    (tester) async {
      final initial = {'name': 'Comércio de teste', 'category': 'Comércio'};
      final reference = _Reference(initial);
      final dynamic editor = await _mount(
        tester,
        reference: reference,
        initial: initial,
        collection: 'establishments',
      );

      for (final (field, invalid) in <(String, String)>[
        ('whatsapp', 'abc21999999999'),
        ('phone', 'https://example.com/21999999999'),
        ('instagram', 'https://instagram.com.evil.invalid/loja'),
        ('maps', 'http://maps.google.com/?q=loja'),
      ]) {
        switch (field) {
          case 'whatsapp':
            editor.whatsapp.text = invalid;
          case 'phone':
            editor.phone.text = invalid;
          case 'instagram':
            editor.instagram.text = invalid;
          case 'maps':
            editor.maps.text = invalid;
        }
        await editor.save();
        await tester.pump();
        expect(reference.writes, isEmpty, reason: '$field should be rejected');
        switch (field) {
          case 'whatsapp':
            editor.whatsapp.clear();
          case 'phone':
            editor.phone.clear();
          case 'instagram':
            editor.instagram.clear();
          case 'maps':
            editor.maps.clear();
        }
      }
    },
  );

  testWidgets('establishment editor rejects unsafe new media URLs', (
    tester,
  ) async {
    final initial = {'title': 'Comércio de teste'};
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
      collection: 'establishments',
    );
    editor.logoUrl.text = 'javascript:alert(1)';

    await editor.save();
    await tester.pump();

    expect(ref.writes, isEmpty);
    expect(find.textContaining('URL HTTPS válida'), findsOneWidget);
  });

  testWidgets('establishment gallery rejects non-HTTPS media input', (
    tester,
  ) async {
    final initial = {'title': 'Comércio de teste'};
    final dynamic editor = await _mount(
      tester,
      reference: _Reference(initial),
      initial: initial,
      collection: 'establishments',
    );
    await _selectBusinessStep(tester, 2);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller == editor.galleryInput,
      ),
      'javascript:alert(1)',
    );
    await tester.tap(find.text('Adicionar à galeria'));
    await tester.pump();

    expect(editor.galleryItems, isEmpty);
    expect(
      find.text('As fotos precisam usar URLs HTTPS válidas.'),
      findsOneWidget,
    );
  });

  testWidgets('establishment editor preserves unchanged legacy URLs', (
    tester,
  ) async {
    final initial = {
      'title': 'Comércio legado',
      'link': 'javascript:legacy-value',
      'galleryUrls': ['http://legacy.example.invalid/old.jpg'],
    };
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
      collection: 'establishments',
    );

    await editor.save();
    await tester.pump();

    expect(ref.writes, hasLength(1));
    expect(ref.stored['link'], initial['link']);
    expect(ref.stored['galleryUrls'], initial['galleryUrls']);
  });

  testWidgets(
    'establishment editor previews unsaved content and saves videos',
    (tester) async {
      final initial = {
        'name': 'Café antigo',
        'category': 'Comércio',
        'published': false,
        'active': false,
      };
      final reference = _Reference(initial);
      final dynamic editor = await _mount(
        tester,
        reference: reference,
        initial: initial,
        collection: 'establishments',
      );

      editor.title.text = 'Café da Serra';
      editor.imageUrl.text = _a;
      editor.galleryItems
        ..clear()
        ..addAll([_a, _b]);
      editor.videoUrls.text =
          'https://youtu.be/abc123\nhttps://vimeo.com/123456';
      editor.whatsapp.text = '5521999999999';
      editor.phone.text = '552133333333';
      editor.instagram.text = '@cafedaserra';
      editor.maps.text = 'https://maps.google.com/?q=Cafe+da+Serra';
      await tester.tap(find.byTooltip('Pré-visualizar perfil'));
      await tester.pumpAndSettle();

      final media = tester.widget<BusinessHeroMedia>(
        find.byType(BusinessHeroMedia),
      );
      expect(find.text('Café da Serra'), findsOneWidget);
      expect(media.business.displayImageUrls, [_a, _b]);
      expect(find.text('Prévia · alterações ainda não salvas'), findsOneWidget);
      expect(find.text('Assistir vídeo'), findsNWidgets(2));
      expect(find.text('Vídeo 1'), findsOneWidget);
      expect(find.text('WhatsApp'), findsNothing);
      expect(find.text('Ligar'), findsNothing);
      expect(find.text('Instagram'), findsNothing);
      expect(find.text('Como chegar'), findsOneWidget);
      expect(reference.writes, isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      editor.publicContactApproved = true;
      await tester.tap(find.byTooltip('Pré-visualizar perfil'));
      await tester.pumpAndSettle();
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Ligar'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
      expect(reference.writes, isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _save(tester, editor);
      expect(reference.stored['videoUrls'], [
        'https://youtu.be/abc123',
        'https://vimeo.com/123456',
      ]);
      expect(reference.stored['publicContactApproved'], isTrue);
      expect(reference.stored['whatsapp'], '5521999999999');
      expect(reference.stored['phone'], '552133333333');
      expect(reference.stored['instagram'], '@cafedaserra');
      expect(
        reference.stored['maps'],
        'https://maps.google.com/?q=Cafe+da+Serra',
      );
    },
  );

  testWidgets(
    'establishment editor rejects video providers outside allowlist',
    (tester) async {
      final initial = {'name': 'Comércio', 'category': 'Comércio'};
      final reference = _Reference(initial);
      final dynamic editor = await _mount(
        tester,
        reference: reference,
        initial: initial,
        collection: 'establishments',
      );
      editor.videoUrls.text = 'https://example.com/track';

      await editor.save();
      await tester.pump();

      expect(reference.writes, isEmpty);
      expect(
        find.textContaining('vídeos devem usar YouTube ou Vimeo'),
        findsOneWidget,
      );
    },
  );

  testWidgets('jobs keep administrative contacts out of public save data', (
    tester,
  ) async {
    final repository = _JobRepository();
    final dynamic editor = await _mount(
      tester,
      collection: 'jobs',
      jobRepository: repository,
    );
    editor.title.text = 'Vaga de teste';
    editor.contact.text = 'admin@example.invalid';
    editor.phone.text = '5550100';
    editor.whatsapp.text = 'https://wa.me/5550100';
    editor.link.text = 'https://example.invalid/private';
    editor.instagram.text = 'https://instagram.com/admin';
    editor.maps.text = 'https://maps.example.invalid/admin';
    editor.additionalInfo.text = 'Notas administrativas';
    editor.eventDate.text = 'não aplicável a vaga';

    final publicData = Map<String, dynamic>.from(editor.prepareSaveData());
    expect(
      publicData.keys.toSet().intersection({
        'contact',
        'phone',
        'whatsapp',
        'link',
        'instagram',
        'maps',
        'mapsUrl',
        'additionalInfo',
        'eventDate',
        'date',
      }),
      isEmpty,
    );
    await _save(tester, editor);

    expect(repository.creates, 1);
    expect(
      repository.createdPublic!.keys.toSet().intersection({
        'contact',
        'phone',
        'whatsapp',
        'link',
        'instagram',
        'maps',
        'mapsUrl',
        'additionalInfo',
        'eventDate',
        'date',
      }),
      isEmpty,
    );
    expect(repository.createdPrivate, {
      'contact': 'admin@example.invalid',
      'phone': '5550100',
      'whatsapp': 'https://wa.me/5550100',
      'link': 'https://example.invalid/private',
      'instagram': 'https://instagram.com/admin',
      'maps': 'https://maps.example.invalid/admin',
      'mapsUrl': 'https://maps.example.invalid/admin',
      'additionalInfo': 'Notas administrativas',
    });
    expect(
      find.textContaining('Não foi possível confirmar a gravação da vaga'),
      findsNothing,
    );
  });

  testWidgets('editing public job fields preserves private contacts', (
    tester,
  ) async {
    final repository = _JobRepository(
      privateData: {
        'contact': 'admin@example.invalid',
        'phone': '5550100',
        'whatsapp': 'https://wa.me/5550100',
        'link': 'https://example.invalid/private',
        'instagram': 'https://instagram.com/admin',
        'maps': 'https://maps.example.invalid/admin',
        'mapsUrl': 'https://maps.example.invalid/admin',
        'additionalInfo': 'Notas administrativas',
      },
    );
    final initial = {
      'title': 'Vaga antiga',
      'contact': 'legacy-contact',
      'instagram': 'legacy-instagram',
      'maps': 'legacy-maps',
      'additionalInfo': 'legacy-notes',
      'eventDate': 'legacy-date',
      'date': 'legacy-date',
    };
    final dynamic editor = await _mount(
      tester,
      collection: 'jobs',
      reference: _Reference(initial),
      initial: initial,
      jobRepository: repository,
    );
    await tester.pumpAndSettle();
    expect(editor.contact.text, 'admin@example.invalid');
    expect(editor.instagram.text, 'https://instagram.com/admin');
    expect(editor.maps.text, 'https://maps.example.invalid/admin');
    expect(editor.additionalInfo.text, 'Notas administrativas');
    expect(editor.eventDate.text, isEmpty);
    editor.description.text = 'Descrição atualizada';
    await _save(tester, editor);

    expect(repository.updatedId, 'doc-id');
    expect(
      repository.updatedPublic!.keys.toSet().intersection({
        'contact',
        'phone',
        'whatsapp',
        'link',
        'instagram',
        'maps',
        'mapsUrl',
        'additionalInfo',
        'eventDate',
        'date',
      }),
      isEmpty,
    );
    expect(repository.updatedPrivate, isEmpty);
  });

  testWidgets('explicitly clearing private contacts saves empty field state', (
    tester,
  ) async {
    final repository = _JobRepository(
      privateData: {
        'contact': 'admin@example.invalid',
        'instagram': 'https://instagram.com/admin',
        'maps': 'https://maps.example.invalid/admin',
        'additionalInfo': 'Notas administrativas',
      },
    );
    final initial = {'title': 'Vaga'};
    final dynamic editor = await _mount(
      tester,
      collection: 'jobs',
      reference: _Reference(initial),
      initial: initial,
      jobRepository: repository,
    );
    await tester.pumpAndSettle();
    editor.contact.clear();
    editor.instagram.clear();
    editor.maps.clear();
    editor.additionalInfo.clear();
    await _save(tester, editor);
    expect(repository.updatedPrivate!['contact'], '');
    expect(repository.updatedPrivate!['instagram'], '');
    expect(repository.updatedPrivate!['maps'], '');
    expect(repository.updatedPrivate!['mapsUrl'], '');
    expect(repository.updatedPrivate!['additionalInfo'], '');
  });

  testWidgets(
    'failed private read blocks saving without overwriting contacts',
    (tester) async {
      final repository = _JobRepository(readError: StateError('denied'));
      final initial = {'title': 'Vaga', 'contact': 'legacy-contact'};
      final dynamic editor = await _mount(
        tester,
        collection: 'jobs',
        reference: _Reference(initial),
        initial: initial,
        jobRepository: repository,
      );
      await tester.pumpAndSettle();
      expect(editor.contact.text, isEmpty);
      expect(editor.instagram.text, isEmpty);
      expect(editor.maps.text, isEmpty);
      expect(editor.additionalInfo.text, isEmpty);
      expect(editor.eventDate.text, isEmpty);
      await editor.save();
      expect(repository.updates, 0);
    },
  );

  testWidgets('legacy job without private doc is identified and protected', (
    tester,
  ) async {
    final repository = _JobRepository(
      readError: AdminJobException('failed-precondition'),
    );
    final initial = {
      'title': 'Vaga antiga',
      'contact': 'legacy-contact',
      'instagram': 'legacy-instagram',
      'maps': 'legacy-maps',
      'additionalInfo': 'legacy-notes',
      'eventDate': 'legacy-date',
      'date': 'legacy-date',
    };
    final dynamic editor = await _mount(
      tester,
      collection: 'jobs',
      reference: _Reference(initial),
      initial: initial,
      jobRepository: repository,
    );
    await tester.pumpAndSettle();
    expect(find.text('Vaga legada pendente de migração'), findsOneWidget);
    expect(editor.contact.text, isEmpty);
    expect(editor.instagram.text, isEmpty);
    expect(editor.maps.text, isEmpty);
    expect(editor.additionalInfo.text, isEmpty);
    expect(editor.eventDate.text, isEmpty);
    await editor.save();
    expect(repository.updates, 0);
  });

  testWidgets('private write failure does not report a successful save', (
    tester,
  ) async {
    final repository = _JobRepository(writeError: StateError('offline'));
    final dynamic editor = await _mount(
      tester,
      collection: 'jobs',
      jobRepository: repository,
    );
    editor.title.text = 'Vaga';
    await editor.save();
    await tester.pump();
    expect(
      find.textContaining('Não foi possível confirmar a gravação da vaga'),
      findsOneWidget,
    );
    expect(repository.creates, 0);
  });
  testWidgets('editing preserves unknown fields and concurrent extra values', (
    tester,
  ) async {
    final initial = _initial();
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    ref.stored['concurrentExtra'] = 'written after editor opened';
    editor.description.text = 'Nova descrição';
    await _save(tester, editor);
    expect(ref.stored['legacyField'], 'preservar');
    expect(ref.stored['concurrentExtra'], 'written after editor opened');
    expect(ref.writes.single.containsKey('legacyField'), isFalse);
  });

  testWidgets('editing preserves an unknown nested map intact', (tester) async {
    final initial = _initial();
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    editor.description.text = 'Nova descrição';
    await _save(tester, editor);
    expect(ref.stored['metadata'], initial['metadata']);
    expect(ref.writes.single.containsKey('metadata'), isFalse);
  });

  testWidgets('known fields replace their previous values', (tester) async {
    final initial = _initial();
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    editor.description.text = 'Nova descrição';
    editor.published = false;
    await _save(tester, editor);
    expect(ref.stored['description'], 'Nova descrição');
    expect(ref.stored['published'], false);
  });

  testWidgets('clearing a known text field does not restore its old value', (
    tester,
  ) async {
    final initial = _initial();
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    editor.description.clear();
    await _save(tester, editor);
    expect(ref.stored['description'], '');
  });

  testWidgets('removed gallery image does not return after saving', (
    tester,
  ) async {
    final initial = _initial();
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    _gallery(tester).onRemove(1);
    await tester.pump();
    await _save(tester, editor);
    expect(ref.stored['galleryUrls'], [_a, _c]);
    expect(ref.stored['imageUrl'], _a);
  });

  testWidgets('gallery changes preserve legacy fields and alternate media', (
    tester,
  ) async {
    final initial = _initial()..['images'] = ['legacy media'];
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    _gallery(tester).onCover(2);
    await tester.pump();
    _gallery(tester).onRemove(1);
    await tester.pump();
    await _save(tester, editor);
    expect(ref.stored['galleryUrls'], [_c, _b]);
    expect(ref.stored['imageUrl'], _c);
    expect(ref.stored['legacyField'], 'preservar');
    expect(ref.stored['images'], ['legacy media']);
  });

  testWidgets(
    'new document prepares the same creation fields without deletes',
    (tester) async {
      final dynamic editor = await _mount(tester);
      editor.title.text = 'Novo evento';
      editor.description.text = 'Descrição';
      final data = Map<String, dynamic>.from(editor.prepareSaveData());
      expect(data.keys.toSet(), {
        'title',
        'description',
        'link',
        'imageUrl',
        'artwork',
        'galleryUrls',
        'category',
        'location',
        'address',
        'eventDate',
        'date',
        'contact',
        'whatsapp',
        'phone',
        'instagram',
        'maps',
        'additionalInfo',
        'published',
        'updatedAt',
      });
      expect(data['title'], 'Novo evento');
      expect(data['description'], 'Descrição');
      expect(data['galleryUrls'], isEmpty);
      expect(data['published'], !BetaEnvironment.enabled);
      expect(data['updatedAt'], FieldValue.serverTimestamp());
      expect(data.values, isNot(contains(FieldValue.delete())));
    },
  );

  testWidgets('clearing expiry intentionally deletes the existing expiry', (
    tester,
  ) async {
    final initial = _initial()
      ..['expiresAt'] = Timestamp.fromDate(DateTime(2030, 1, 1));
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    editor.expires.clear();
    await _save(tester, editor);
    expect(ref.stored.containsKey('expiresAt'), isFalse);
    expect(ref.writes.single['expiresAt'], FieldValue.delete());
  });

  testWidgets('timestamps and publication extras remain outside the patch', (
    tester,
  ) async {
    final initial = _initial()
      ..addAll({
        'createdAt': Timestamp.fromDate(DateTime(2020)),
        'publishedAt': Timestamp.fromDate(DateTime(2021)),
        'active': false,
        'status': 'approved',
        'order': 40,
      });
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    final currentCreatedAt = Timestamp.fromDate(DateTime(2019));
    ref.stored['createdAt'] = currentCreatedAt;
    await _save(tester, editor);
    expect(ref.stored['createdAt'], currentCreatedAt);
    for (final key in ['publishedAt', 'active', 'status', 'order']) {
      expect(ref.stored[key], initial[key]);
      expect(ref.writes.single.containsKey(key), isFalse);
    }
    expect(ref.writes.single['updatedAt'], FieldValue.serverTimestamp());
    expect(ref.writes.single.containsKey('createdAt'), isFalse);
  });

  testWidgets('business logo and complete gallery can still be cleared', (
    tester,
  ) async {
    final initial = _initial()..['logoUrl'] = 'https://example.com/logo.jpg';
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
      collection: 'establishments',
    );
    await _selectBusinessStep(tester, 2);
    editor.logoUrl.clear();
    for (var i = 0; i < 3; i++) {
      _gallery(tester).onRemove(0);
      await tester.pump();
    }
    await _save(tester, editor);
    expect(ref.stored['logoUrl'], '');
    expect(ref.stored['imageUrl'], '');
    expect(ref.stored['galleryUrls'], isEmpty);
    expect(ref.stored['legacyField'], 'preservar');
  });
}
