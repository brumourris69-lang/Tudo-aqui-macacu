import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/supabase_search_pilot_config.dart';
import 'package:tudo_aqui_macacu/main_supabase_pilot.dart';

const projectRef = 'zzxvcunuwbhglzzklsrl';
const projectUrl = 'https://$projectRef.supabase.co';
const publicKey = 'sb_publishable_test_key_only';

void main() {
  testWidgets(
    'invalid pilot config blocks before transport/bootstrap creation',
    (tester) async {
      var bootstrapCalls = 0;
      await tester.pumpWidget(
        buildSupabaseSearchPilotApp(
          debug: true,
          flavor: 'supabasePilot',
          projectRef: '',
          url: projectUrl,
          anonKey: publicKey,
          createPilot: (_) {
            bootstrapCalls++;
            return const Text('Busca ativa');
          },
        ),
      );

      expect(find.text('Busca Supabase indisponível'), findsOneWidget);
      expect(bootstrapCalls, 0);
    },
  );

  testWidgets('valid pilot config enters only the injected Supabase root', (
    tester,
  ) async {
    SupabaseSearchPilotConfig? received;
    await tester.pumpWidget(
      buildSupabaseSearchPilotApp(
        debug: true,
        flavor: 'supabasePilot',
        projectRef: projectRef,
        url: projectUrl,
        anonKey: publicKey,
        createPilot: (config) {
          received = config;
          return const Text('Busca Supabase piloto');
        },
      ),
    );

    expect(find.text('Busca Supabase piloto'), findsOneWidget);
    expect(received?.projectRef, projectRef);
  });

  testWidgets('wrong or absent Android flavor blocks pilot before transport', (
    tester,
  ) async {
    for (final flavor in [null, 'searchLocal', 'production']) {
      var bootstrapCalls = 0;
      await tester.pumpWidget(
        buildSupabaseSearchPilotApp(
          debug: true,
          flavor: flavor,
          projectRef: projectRef,
          url: projectUrl,
          anonKey: publicKey,
          createPilot: (_) {
            bootstrapCalls++;
            return const Text('Busca ativa');
          },
        ),
      );

      expect(find.text('Busca Supabase indisponível'), findsOneWidget);
      expect(bootstrapCalls, 0);
    }
  });
}
