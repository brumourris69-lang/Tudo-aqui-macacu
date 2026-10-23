import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tudo_aqui_macacu/core/config/supabase_search_pilot_config.dart';
import 'package:tudo_aqui_macacu/features/search/models/search_result.dart';
import 'package:tudo_aqui_macacu/features/search/policies/business_search_policy.dart';
import 'package:tudo_aqui_macacu/features/search/repositories/supabase_search_pilot_repository.dart';
import 'package:tudo_aqui_macacu/features/search/repositories/universal_search_repository.dart';

const projectRef = 'zzxvcunuwbhglzzklsrl';
const publicKey = 'sb_publishable_test_key_only';

SupabaseSearchPilotConfig config() => SupabaseSearchPilotConfig.fromDefines(
  debug: true,
  projectRef: projectRef,
  url: 'https://$projectRef.supabase.co',
  anonKey: publicKey,
);

Map<String, Object?> row(String id, {bool hasMore = false}) => {
  'id': id,
  'name': 'Nome público fictício',
  'summary': 'Resumo público',
  'category': 'Comércio',
  'subcategory': 'Livraria',
  'image_url': '',
  'has_more': hasMore,
};

class RecordingClient extends http.BaseClient {
  RecordingClient(this.response);
  final Future<http.Response> Function(http.BaseRequest request) response;
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    final result = await response(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(result.body)),
      result.statusCode,
      headers: result.headers,
    );
  }
}

void main() {
  test(
    'search uses fixed RPC and public key with explicit result projection',
    () async {
      final client = RecordingClient(
        (_) async => http.Response(
          jsonEncode([row('pilot-oficina-exemplo', hasMore: true)]),
          200,
        ),
      );
      final repository = SupabaseSearchPilotRepository(
        config: config(),
        client: client,
      );
      final request = BusinessSearchRequest(query: 'Café Macacu', limit: 1);

      final page = await repository.search(request);

      expect(
        client.lastRequest?.url.path,
        '/rest/v1/rpc/search_public_establishments',
      );
      expect(client.lastRequest?.url.host, '$projectRef.supabase.co');
      expect(client.lastRequest?.headers['apikey'], publicKey);
      expect(client.lastRequest?.headers['authorization'], 'Bearer $publicKey');
      expect(jsonDecode((client.lastRequest as http.Request).body), {
        'p_query': 'cafe macacu',
        'p_category': 'all',
        'p_page_size': 1,
        'p_cursor_id': null,
      });
      expect(page.results.single.type, SearchResultType.establishment);
      expect(page.results.single.title, 'Nome público fictício');
      expect(page.nextCursor?.queryKey, request.queryKey);
      expect(
        page.nextCursor?.lastIndexId,
        'establishments__pilot-oficina-exemplo',
      );
      repository.close();
    },
  );

  test('rejects query boundaries before making an RPC request', () async {
    var calls = 0;
    final client = RecordingClient((_) async {
      calls++;
      return http.Response('[]', 200);
    });
    final repository = SupabaseSearchPilotRepository(
      config: config(),
      client: client,
    );

    for (final query in [
      '',
      'x' * 81,
      'duas palavras aqui agora cinco',
      'palavra x',
      'a' * 25,
    ]) {
      expect(
        () => BusinessSearchRequest(query: query),
        throwsA(isA<SearchQueryValidationException>()),
        reason: 'consulta inválida: $query',
      );
    }
    for (final query in ['palavra x', 'a' * 25]) {
      await expectLater(
        () => repository.search(BusinessSearchRequest(query: query)),
        throwsA(isA<SearchQueryValidationException>()),
      );
    }
    expect(calls, 0);
    repository.close();
  });

  test('detail resolves only a validated public establishment by ID', () async {
    final client = RecordingClient(
      (_) async => http.Response(
        jsonEncode([
          {
            'id': 'pilot-livraria-exemplo',
            'name': 'Livraria Exemplo',
            'summary': 'Resumo',
            'category': 'Comércio',
            'subcategory': 'Livraria',
            'image_url': '',
          },
        ]),
        200,
      ),
    );
    final repository = SupabaseSearchPilotRepository(
      config: config(),
      client: client,
    );

    final business = await repository.getPublicBusiness(
      'pilot-livraria-exemplo',
    );

    expect(
      client.lastRequest?.url.path,
      '/rest/v1/rpc/get_public_establishment',
    );
    expect(jsonDecode((client.lastRequest as http.Request).body), {
      'p_id': 'pilot-livraria-exemplo',
    });
    expect(business?.id, 'pilot-livraria-exemplo');
    expect(business?.name, 'Livraria Exemplo');
    expect(business?.phone, isEmpty);
    repository.close();
  });

  test('has_more false does not expose a next-page cursor', () async {
    final client = RecordingClient(
      (_) async => http.Response(
        jsonEncode([row('pilot-livraria-exemplo', hasMore: false)]),
        200,
      ),
    );
    final repository = SupabaseSearchPilotRepository(
      config: config(),
      client: client,
    );

    final page = await repository.search(
      BusinessSearchRequest(query: 'livraria'),
    );

    expect(page.results, hasLength(1));
    expect(page.nextCursor, isNull);
    repository.close();
  });

  test(
    'detail rejects a public row whose ID differs from the request',
    () async {
      final client = RecordingClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'id': 'pilot-outra-vaga',
              'name': 'Outro registro fictício',
              'summary': 'Resumo',
              'category': 'Comércio',
              'subcategory': 'Livraria',
              'image_url': '',
            },
          ]),
          200,
        ),
      );
      final repository = SupabaseSearchPilotRepository(
        config: config(),
        client: client,
      );

      await expectLater(
        repository.getPublicBusiness('pilot-livraria-exemplo'),
        throwsFormatException,
      );
      repository.close();
    },
  );

  test(
    'category filters and keyset cursor are encoded without broadening',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final client = RecordingClient((request) async {
        bodies.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>,
        );
        return http.Response('[]', 200);
      });
      final repository = SupabaseSearchPilotRepository(
        config: config(),
        client: client,
      );
      for (final (filter, expectedCategory) in [
        (BusinessSearchFilter.commerce, 'commerce'),
        (BusinessSearchFilter.services, 'services'),
      ]) {
        await repository.search(
          BusinessSearchRequest(query: 'exemplo', filter: filter),
        );
        expect(bodies.last['p_category'], expectedCategory);
      }
      final cursorRequest = BusinessSearchRequest(
        query: 'exemplo',
        filter: BusinessSearchFilter.commerce,
        cursor: const BusinessSearchCursor(
          'commerce:exemplo',
          'establishments__pilot-cafe-exemplo',
        ),
      );
      await repository.search(cursorRequest);

      expect(bodies[2]['p_cursor_id'], 'pilot-cafe-exemplo');
      expect(bodies[2]['p_page_size'], 20);
      repository.close();
    },
  );

  test(
    'rejects malformed and cross-query/category cursors before RPC',
    () async {
      var calls = 0;
      final client = RecordingClient((_) async {
        calls++;
        return http.Response('[]', 200);
      });
      final repository = SupabaseSearchPilotRepository(
        config: config(),
        client: client,
      );

      final requests = [
        () => BusinessSearchRequest(
          query: 'exemplo',
          cursor: const BusinessSearchCursor(
            'all:exemplo',
            'malformed__pilot-id',
          ),
        ),
        () => BusinessSearchRequest(
          query: 'exemplo',
          cursor: const BusinessSearchCursor(
            'all:outra',
            'establishments__pilot-id',
          ),
        ),
        () => BusinessSearchRequest(
          query: 'exemplo',
          filter: BusinessSearchFilter.services,
          cursor: const BusinessSearchCursor(
            'commerce:exemplo',
            'establishments__pilot-id',
          ),
        ),
      ];

      for (final createRequest in requests) {
        await expectLater(
          () => repository.search(createRequest()),
          throwsArgumentError,
        );
      }
      expect(calls, 0);
      repository.close();
    },
  );

  test(
    'rejects unsupported filters, invalid IDs and private response fields',
    () async {
      var calls = 0;
      final client = RecordingClient((_) async {
        calls++;
        return http.Response(
          jsonEncode([
            {...row('pilot-vazamento'), 'phone': 'private'},
          ]),
          200,
        );
      });
      final repository = SupabaseSearchPilotRepository(
        config: config(),
        client: client,
      );

      await expectLater(
        repository.search(
          BusinessSearchRequest(
            query: 'comercio',
            filter: BusinessSearchFilter.jobs,
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        repository.getPublicBusiness('../private'),
        throwsArgumentError,
      );
      expect(calls, 0);
      repository.close();
    },
  );

  test('rejects unknown fields instead of retaining unapproved data', () async {
    final client = RecordingClient(
      (_) async => http.Response(
        jsonEncode([
          {...row('pilot-vazamento'), 'admin_note': 'não publicar'},
        ]),
        200,
      ),
    );
    final repository = SupabaseSearchPilotRepository(
      config: config(),
      client: client,
    );

    await expectLater(
      repository.search(BusinessSearchRequest(query: 'teste')),
      throwsFormatException,
    );
    repository.close();
  });

  test('maps HTTP errors without retaining server response bodies', () async {
    final client = RecordingClient(
      (_) async => http.Response('{"message":"sensitive server detail"}', 503),
    );
    final repository = SupabaseSearchPilotRepository(
      config: config(),
      client: client,
    );

    await expectLater(
      repository.search(BusinessSearchRequest(query: 'teste')),
      throwsA(
        isA<SupabaseSearchPilotException>().having(
          (error) => error.toString(),
          'sanitized message',
          isNot(contains('sensitive server detail')),
        ),
      ),
    );
    repository.close();
  });

  test('sanitizes transport errors and does not follow redirects', () async {
    final client = RecordingClient((_) async {
      throw const SocketException('private transport diagnostic');
    });
    final repository = SupabaseSearchPilotRepository(
      config: config(),
      client: client,
    );
    await expectLater(
      repository.search(BusinessSearchRequest(query: 'teste')),
      throwsA(
        isA<SupabaseSearchPilotException>().having(
          (error) => error.toString(),
          'sanitized transport failure',
          isNot(contains('private transport diagnostic')),
        ),
      ),
    );
    expect((client.lastRequest as http.Request).followRedirects, isFalse);
    repository.close();
  });

  test('maps timeout and oversized or malformed responses safely', () async {
    final never = Completer<http.Response>();
    final timeoutRepository = SupabaseSearchPilotRepository(
      config: config(),
      client: RecordingClient((_) => never.future),
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(
      timeoutRepository.search(BusinessSearchRequest(query: 'teste')),
      throwsA(isA<SupabaseSearchPilotException>()),
    );
    timeoutRepository.close();

    final emptyRepository = SupabaseSearchPilotRepository(
      config: config(),
      client: RecordingClient((_) async => http.Response('[]', 200)),
    );
    expect(
      (await emptyRepository.search(
        BusinessSearchRequest(query: 'teste'),
      )).results,
      isEmpty,
    );
    emptyRepository.close();

    for (final body in ['{malformed', '"${'x' * 70000}"']) {
      final repository = SupabaseSearchPilotRepository(
        config: config(),
        client: RecordingClient((_) async => http.Response(body, 200)),
      );
      await expectLater(
        repository.search(BusinessSearchRequest(query: 'teste')),
        throwsFormatException,
      );
      repository.close();
    }
  });
}
