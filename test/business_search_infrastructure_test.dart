import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/search/infrastructure/business_search_index.dart';
import 'package:tudo_aqui_macacu/features/search/infrastructure/business_search_server.dart';
import 'package:tudo_aqui_macacu/features/search/policies/business_search_policy.dart';
import 'package:tudo_aqui_macacu/features/search/repositories/universal_search_repository.dart';

class MemoryStore implements BusinessIndexStore, BusinessIndexTransaction {
  final sources = <String, Map<String, dynamic>>{};
  final index = <String, BusinessSearchIndexEntry>{};
  int reads = 0;
  @override
  Future<void> transaction(
    Future<void> Function(BusinessIndexTransaction) body,
  ) => body(this);
  @override
  Future<Map<String, dynamic>?> readCurrentEstablishment(String id) async {
    reads++;
    return sources[id];
  }

  @override
  Future<void> replaceIndex(String id, BusinessSearchIndexEntry entry) async =>
      index[id] = entry;
  @override
  Future<void> deleteIndex(String id) async => index.remove(id);
  @override
  Future<List<BusinessIndexCandidate>> candidates({
    required String anchor,
    required BusinessSearchFilter filter,
    required String? afterIndexId,
    required int limit,
  }) async {
    final entries =
        index.entries
            .where(
              (entry) =>
                  entry.value.prefixes.contains(anchor) &&
                  (filter == BusinessSearchFilter.all ||
                      entry.value.group == filter.name) &&
                  (afterIndexId == null ||
                      entry.key.compareTo(afterIndexId) > 0),
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .take(limit)
        .map(
          (entry) => BusinessIndexCandidate(entry.key, entry.value.result.id),
        )
        .toList();
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 8);
  const access = SearchServerAccess(authenticated: true, appVerified: true);
  Map<String, dynamic> source([String name = 'Elétrica Vieira']) => {
    'name': name,
    'published': true,
    'category': 'Serviços',
    'description': 'Manutenção residencial',
    'adminEmail': 'private',
    'imageUrl': 'https://example.com/image.png',
  };
  late MemoryStore store;
  late BusinessIndexSynchronizer sync;
  late BusinessSearchServer server;
  setUp(() {
    store = MemoryStore();
    sync = BusinessIndexSynchronizer(store, (_) => false);
    server = BusinessSearchServer(store, (_) => false);
  });
  Future<void> add(String id, [String name = 'Elétrica Vieira']) async {
    store.sources[id] = source(name);
    await sync.synchronize(id, now: now);
  }

  Future<BusinessSearchPage> search(
    String query, {
    BusinessSearchFilter filter = BusinessSearchFilter.all,
    int limit = 20,
    BusinessSearchCursor? cursor,
  }) => server.search(
    BusinessSearchRequest(
      query: query,
      filter: filter,
      limit: limit,
      cursor: cursor,
    ),
    access: access,
    now: now,
  );

  test(
    'bounded public index preserves source ID and authorized image only',
    () async {
      await add('AbC');
      final entry = store.index['establishments__AbC']!;
      expect(entry.result.id, 'AbC');
      expect(entry.toMap().keys, isNot(contains('adminEmail')));
      expect(entry.toMap().toString(), isNot(contains('private')));
      expect(entry.result.imageUrl, isEmpty);
      expect(entry.terms, contains('eletrica'));
      expect(entry.prefixes, containsAll(['el', 'ele', 'eletrica']));
      expect(entry.prefixes, isNot(contains('e')));
      expect(entry.prefixes.length, lessThanOrEqualTo(64 * 23));
      final authorized = BusinessSearchIndexEntry.build(
        'AbC',
        source(),
        now: now,
        authorizeImage: (url) => url == 'https://example.com/image.png',
      )!;
      expect(authorized.result.imageUrl, isNotEmpty);
    },
  );
  test(
    'repeated and delayed events reconcile current state with stable identity',
    () async {
      await add('one');
      await sync.synchronize('one', now: now);
      expect(store.index.length, 1);
      store.sources['one'] = source('Padaria Nova');
      await sync.synchronize(
        'one',
        now: now,
      ); // late event still reads current source
      expect(store.index.values.single.prefixes, isNot(contains('eletrica')));
      expect(store.index.values.single.terms, contains('padaria'));
    },
  );
  test(
    'unpublish deactivate delete expire and malformed state remove index',
    () async {
      for (final state in [
        <String, dynamic>{'published': false},
        {'active': false},
        {'expiresAt': Timestamp.fromDate(now)},
        {'published': 'true'},
      ]) {
        await add('one');
        store.sources['one']!.addAll(state);
        await sync.synchronize('one', now: now);
        expect(store.index, isEmpty);
      }
      await add('one');
      store.sources.remove('one');
      await sync.synchronize('one', now: now);
      expect(store.index, isEmpty);
    },
  );
  test(
    'stale index never returns unpublished inactive expired or deleted source',
    () async {
      for (final state in [
        <String, dynamic>{'published': false},
        {'active': false},
        {'expiresAt': Timestamp.fromDate(now)},
      ]) {
        await add('one');
        store.sources['one']!.addAll(state);
        expect((await search('eletrica')).results, isEmpty);
      }
      await add('one');
      store.sources.remove('one');
      expect((await search('eletrica')).results, isEmpty);
    },
  );
  test('result uses current display data and validates all words', () async {
    await add('one');
    store.sources['one']!['name'] = 'Elétrica Silva';
    expect((await search('eletrica vieira')).results, isEmpty);
    expect(
      (await search('ELÉTRICA sil')).results.single.title,
      'Elétrica Silva',
    );
  });
  test('filters revalidate current category despite stale index', () async {
    await add('one');
    store.sources['one']!['category'] = 'Tecnologia';
    expect(
      (await search('eletrica', filter: BusinessSearchFilter.services)).results,
      isEmpty,
    );
    expect((await search('eletrica')).results.single.category, 'Tecnologia');
  });
  test('access is validated before storage is read', () async {
    for (final rejected in [
      const SearchServerAccess(authenticated: false, appVerified: true),
      const SearchServerAccess(authenticated: true, appVerified: false),
    ]) {
      await expectLater(
        server.search(
          BusinessSearchRequest(query: 'eletrica'),
          access: rejected,
          now: now,
        ),
        throwsStateError,
      );
    }
    expect(store.reads, 0);
  });
  test('request rejects unbounded query limits and mismatched cursors', () {
    for (final query in [
      '',
      'a',
      List.filled(81, 'a').join(),
      'aa bb cc dd ee',
    ]) {
      expect(() => BusinessSearchRequest(query: query), throwsArgumentError);
    }
    expect(
      () => BusinessSearchRequest(query: 'eletrica', limit: 21),
      throwsArgumentError,
    );
    expect(
      () => BusinessSearchRequest(
        query: 'eletrica',
        cursor: const BusinessSearchCursor('other', 'id'),
      ),
      throwsArgumentError,
    );
  });
  test('equivalent word order keeps anchor and pagination query identity', () {
    final first = BusinessSearchRequest(query: 'vieira silvaa');
    final second = BusinessSearchRequest(query: 'silvaa vieira');
    expect(first.anchor, second.anchor);
    expect(first.queryKey, second.queryKey);
  });
  test(
    'page cursor follows last consumed candidate without skipping valid rows',
    () async {
      for (var n = 0; n < 3; n++) {
        await add('id$n');
      }
      final first = await search('eletrica', limit: 1);
      final second = await search(
        'eletrica',
        limit: 1,
        cursor: first.nextCursor,
      );
      final third = await search(
        'eletrica',
        limit: 1,
        cursor: second.nextCursor,
      );
      expect(
        [
          ...first.results,
          ...second.results,
          ...third.results,
        ].map((r) => r.id),
        ['id0', 'id1', 'id2'],
      );
      expect(third.nextCursor, isNull);
    },
  );
  test(
    'stale candidates have bounded reads and allow empty continuation pages',
    () async {
      for (var n = 0; n < 45; n++) {
        final id = 'id${n.toString().padLeft(2, '0')}';
        await add(id);
        store.sources[id]!['published'] = false;
      }
      store.reads = 0;
      final page = await search('eletrica');
      expect(page.results, isEmpty);
      expect(page.nextCursor, isNotNull);
      expect(store.reads, 40);
      final next = await search('eletrica', cursor: page.nextCursor);
      expect(next.nextCursor, isNull);
      expect(store.reads, 45);
    },
  );
  test(
    'expiry without write is blocked at read time then removed by reconciliation',
    () async {
      await add('one');
      store.sources['one']!['expiresAt'] = Timestamp.fromDate(
        now.add(const Duration(minutes: 1)),
      );
      await sync.synchronize('one', now: now);
      final later = now.add(const Duration(minutes: 2));
      expect(
        (await server.search(
          BusinessSearchRequest(query: 'eletrica'),
          access: access,
          now: later,
        )).results,
        isEmpty,
      );
      await sync.synchronize('one', now: later);
      expect(store.index, isEmpty);
    },
  );
}
