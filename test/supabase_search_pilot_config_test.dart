import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/supabase_search_pilot_config.dart';

const pilotRef = 'zzxvcunuwbhglzzklsrl';
const pilotUrl = 'https://$pilotRef.supabase.co';
const publishableKey = 'sb_publishable_test_key_only';
const anotherProjectRef = 'abcdefghijklmnopqrst';

void main() {
  test('accepts an explicit debug pilot identity and HTTPS URL', () {
    final config = SupabaseSearchPilotConfig.fromDefines(
      debug: true,
      projectRef: pilotRef,
      url: pilotUrl,
      anonKey: publishableKey,
    );

    expect(config.projectRef, pilotRef);
    expect(config.url, Uri.parse(pilotUrl));
    expect(config.anonKey, publishableKey);
  });

  test('rejects missing or malformed pilot values', () {
    for (final values in [
      (ref: '', url: pilotUrl, key: publishableKey),
      (ref: pilotRef, url: '', key: publishableKey),
      (ref: pilotRef, url: pilotUrl, key: ''),
      (
        ref: 'short-ref',
        url: 'https://short-ref.supabase.co',
        key: publishableKey,
      ),
      (ref: pilotRef, url: 'http://$pilotRef.supabase.co', key: publishableKey),
      (
        ref: pilotRef,
        url: 'https://otherprojectref.supabase.co',
        key: publishableKey,
      ),
      (
        ref: 'tudo-aqui-macacu',
        url: 'https://tudo-aqui-macacu.supabase.co',
        key: publishableKey,
      ),
      (
        ref: 'demo-universal-search',
        url: 'https://demo-universal-search.supabase.co',
        key: publishableKey,
      ),
    ]) {
      expect(
        () => SupabaseSearchPilotConfig.fromDefines(
          debug: true,
          projectRef: values.ref,
          url: values.url,
          anonKey: values.key,
        ),
        throwsFormatException,
      );
    }
  });

  test('accepts only the explicitly approved pilot project reference', () {
    expect(
      () => SupabaseSearchPilotConfig.fromDefines(
        debug: true,
        projectRef: anotherProjectRef,
        url: 'https://$anotherProjectRef.supabase.co',
        anonKey: publishableKey,
      ),
      throwsFormatException,
    );
  });

  test('rejects release mode and service-role keys', () {
    final serviceRoleJwt = 'header.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature';
    for (final config in [
      (debug: false, key: publishableKey),
      (debug: true, key: 'sb_secret_never_bundle'),
      (debug: true, key: serviceRoleJwt),
    ]) {
      expect(
        () => SupabaseSearchPilotConfig.fromDefines(
          debug: config.debug,
          projectRef: pilotRef,
          url: pilotUrl,
          anonKey: config.key,
        ),
        throwsFormatException,
      );
    }
  });
}
