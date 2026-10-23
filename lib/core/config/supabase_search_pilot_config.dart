import 'dart:convert';

/// Explicit, debug-only identity for the public Supabase search pilot.
/// No values are inferred from Firebase configuration or production defaults.
class SupabaseSearchPilotConfig {
  SupabaseSearchPilotConfig._({
    required this.projectRef,
    required this.url,
    required this.anonKey,
  });

  static const _approvedPilotProjectRef = 'zzxvcunuwbhglzzklsrl';
  static final _projectRefPattern = RegExp(r'^[a-z0-9]{20}$');

  final String projectRef;
  final Uri url;
  final String anonKey;

  static SupabaseSearchPilotConfig fromDefines({
    required bool debug,
    required String projectRef,
    required String url,
    required String anonKey,
  }) {
    final ref = projectRef.trim();
    if (!debug) {
      throw const FormatException(
        'O piloto Supabase está disponível apenas em debug.',
      );
    }
    if (ref != projectRef ||
        ref != _approvedPilotProjectRef ||
        !_projectRefPattern.hasMatch(ref)) {
      throw const FormatException('Identidade do projeto piloto inválida.');
    }

    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null ||
        parsedUrl.scheme != 'https' ||
        parsedUrl.host != '$ref.supabase.co' ||
        parsedUrl.userInfo.isNotEmpty ||
        parsedUrl.hasPort ||
        parsedUrl.hasQuery ||
        parsedUrl.hasFragment ||
        (parsedUrl.path.isNotEmpty && parsedUrl.path != '/')) {
      throw const FormatException('URL do projeto piloto inválida.');
    }

    final key = anonKey;
    if (key.trim() != key ||
        key.length < 12 ||
        key.length > 4096 ||
        key.contains(RegExp(r'\s')) ||
        _isServiceRoleKey(key)) {
      throw const FormatException('Chave pública do piloto inválida.');
    }

    return SupabaseSearchPilotConfig._(
      projectRef: ref,
      url: parsedUrl,
      anonKey: key,
    );
  }

  static bool _isServiceRoleKey(String key) {
    if (key.startsWith('sb_secret_')) return true;
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map && payload['role'] == 'service_role';
    } on FormatException {
      return false;
    }
  }
}
