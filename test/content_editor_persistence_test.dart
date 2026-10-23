import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/admin_job_repository.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

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
    this.privateData,
    this.readError,
    this.writeError,
    this.pendingRead,
    this.pendingWrite,
  });
  Map<String, dynamic>? privateData;
  final Map<String, dynamic> publicData = const {'title': 'Vaga atual'};
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
  _Reference? reference,
  Map<String, dynamic>? initial,
  String collection = 'events',
  AdminJobRepository? jobRepository,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 5000));
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

void main() {
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
        'imageUrl': '',
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
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller == editor.galleryInput,
      ),
      'javascript:alert(1)',
    );
    await tester.tap(find.text('Adicionar / atualizar fotos'));
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
      expect(data['published'], true);
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
