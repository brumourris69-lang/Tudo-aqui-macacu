import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;

import 'core/config/supabase_search_pilot_config.dart';
import 'core/theme/app_colors.dart';
import 'features/search/pages/universal_search_page.dart';
import 'features/search/policies/business_search_policy.dart';
import 'features/search/repositories/supabase_search_pilot_repository.dart';

const supabasePilotProjectRef = String.fromEnvironment(
  'SUPABASE_PILOT_PROJECT_REF',
);
const supabasePilotUrl = String.fromEnvironment('SUPABASE_PILOT_URL');
const supabasePilotAnonKey = String.fromEnvironment('SUPABASE_PILOT_ANON_KEY');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    buildSupabaseSearchPilotApp(
      debug: kDebugMode,
      flavor: appFlavor,
      projectRef: supabasePilotProjectRef,
      url: supabasePilotUrl,
      anonKey: supabasePilotAnonKey,
    ),
  );
}

/// Parses all compile-time values before constructing any pilot transport.
/// This entrypoint deliberately does not import or initialize Firebase.
Widget buildSupabaseSearchPilotApp({
  required bool debug,
  required String? flavor,
  required String projectRef,
  required String url,
  required String anonKey,
  Widget Function(SupabaseSearchPilotConfig config)? createPilot,
}) {
  late final Widget home;
  try {
    if (flavor != 'supabasePilot') {
      throw const FormatException('Flavor Supabase piloto inválida.');
    }
    final config = SupabaseSearchPilotConfig.fromDefines(
      debug: debug,
      projectRef: projectRef,
      url: url,
      anonKey: anonKey,
    );
    home = createPilot?.call(config) ?? _createPilotSearch(config);
  } on FormatException {
    home = const _PilotBlockedView();
  }

  return MaterialApp(
    title: 'Tudo Aqui Macacu — piloto de busca',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.soft,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.sky,
        primary: AppColors.sky,
        secondary: AppColors.orange,
        surface: Colors.white,
      ),
    ),
    home: home,
  );
}

Widget _createPilotSearch(SupabaseSearchPilotConfig config) {
  final repository = SupabaseSearchPilotRepository(config: config);
  return UniversalSearchPage(
    repository: repository,
    resolveBusiness: repository.getPublicBusiness,
    supportedFilters: const {
      BusinessSearchFilter.all,
      BusinessSearchFilter.commerce,
      BusinessSearchFilter.services,
    },
    trackBusinessShareMetrics: false,
  );
}

class _PilotBlockedView extends StatelessWidget {
  const _PilotBlockedView();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Busca Supabase indisponível', textAlign: TextAlign.center),
      ),
    ),
  );
}
