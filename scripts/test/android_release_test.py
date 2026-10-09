import importlib.util
from pathlib import Path
import unittest
import tempfile
import shutil

spec = importlib.util.spec_from_file_location('android_release', Path(__file__).parents[1] / 'android_release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
CERT = 'AB' * 32  # Public synthetic fingerprint; no keystore or private key.


class AndroidReleaseTest(unittest.TestCase):
    def test_static_repository_guards(self):
        release.static_checks()

    def test_static_checks_detect_configuration_regressions(self):
        files = ['android/app/build.gradle.kts', 'firebase/android/google-services.json',
                 '.github/workflows/main.yml', 'codemagic.yaml']
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in files:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(release.ROOT / name, target)
            for name, old, new in [
                (files[0], 'signingConfig = signingConfigs.getByName("authorizedRelease")',
                 'signingConfig = signingConfigs.getByName("debug")'),
                (files[0], 'isDebuggable = false', 'isDebuggable = true'),
                (files[0], 'gradle.taskGraph.whenReady', 'removedGuard'),
                (files[2], 'environment: android-release', 'environment: unprotected'),
                (files[2], "github.ref == 'refs/heads/main'", "github.ref == 'refs/heads/untrusted'"),
                (files[1], '"project_id": "tudo-aqui-macacu"', '"project_id": "demo-universal-search"'),
            ]:
                with self.subTest(name=name, guard=old):
                    path = root / name
                    original = path.read_text(encoding='utf-8')
                    self.assertIn(old, original)
                    path.write_text(original.replace(old, new), encoding='utf-8')
                    try:
                        with self.assertRaises(release.ReleaseError):
                            release.static_checks(root)
                    finally:
                        path.write_text(original, encoding='utf-8')

    def test_authorization_is_explicit(self):
        for env in [{}, {'ANDROID_RELEASE_AUTHORIZED': 'true'},
                    {'ANDROID_RELEASE_CERT_SHA256': CERT}]:
            with self.assertRaises(release.ReleaseError):
                release.preflight(env)
        release.preflight({'ANDROID_RELEASE_AUTHORIZED': 'true', 'ANDROID_RELEASE_CERT_SHA256': CERT})

    def test_ci_rejects_pull_requests_and_untrusted_refs(self):
        env = dict(CI='true', ANDROID_RELEASE_AUTHORIZED='true', ANDROID_RELEASE_CERT_SHA256=CERT,
                   BUNDLETOOL_VERSION='1.18.3', BUNDLETOOL_SHA256='CD' * 32,
                   GITHUB_EVENT_NAME='workflow_dispatch', GITHUB_REF='refs/heads/main')
        release.preflight(env)
        for change in [dict(GITHUB_EVENT_NAME='pull_request'), dict(GITHUB_EVENT_NAME='pull_request_target'),
                       dict(GITHUB_REF='refs/heads/untrusted'), dict(BUNDLETOOL_SHA256=''),
                       dict(BUNDLETOOL_VERSION='untrusted')]:
            with self.assertRaises(release.ReleaseError):
                release.preflight({**env, **change})

    def test_manifest_official_and_not_debuggable(self):
        xml = f'<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{release.APP_ID}"><application android:debuggable="false"/></manifest>'
        release.validate_manifest(xml)
        for invalid in [xml.replace('false', 'true'), xml.replace(release.APP_ID, release.APP_ID + '.searchlocal'),
                        xml.replace('</manifest>', '<instrumentation/></manifest>'),
                        xml.replace('/>', '><service android:name="LocalIsolationVpnService"/></application>'),
                        xml.replace('/>', '><service android:name=".SearchLocalVpnService"/></application>')]:
            with self.assertRaises(release.ReleaseError):
                release.validate_manifest(invalid)

    def test_certificates_must_match_and_debug_is_never_authorized(self):
        release.validate_certificate('Signer #1 certificate SHA-256 digest: ' + CERT, CERT)
        release.validate_certificate('SHA256: ' + ':'.join(['AB'] * 32), CERT)
        for invalid in ['SHA256: ' + 'CD' * 32, 'Owner: CN=Android Debug\nSHA256: ' + CERT, '',
                        'SHA256: ' + CERT + '\nSHA256: ' + 'CD' * 32]:
            with self.assertRaises(release.ReleaseError):
                release.validate_certificate(invalid, CERT)

    def test_private_material_rejected_but_public_firebase_ids_allowed(self):
        for name in ['assets/key.properties', 'assets/release.jks', '.env', 'service-account.json', 'private.pem']:
            self.assertTrue(release.forbidden_path(name))
        self.assertFalse(release.forbidden_path('google-services.json'))
        self.assertTrue(release.scan_secret(b'-----BEGIN PRIVATE KEY-----'))
        self.assertTrue(release.scan_secret(b'{"private_key": "synthetic"}'))
        self.assertFalse(release.scan_secret(b'{"project_id": "tudo-aqui-macacu", "api_key": "public-id"}'))

    def test_packaged_firebase_test_configuration_is_rejected(self):
        release.validate_resources(b'project_id:tudo-aqui-macacu')
        release.validate_resources('tudo-aqui-macacu'.encode('utf-16-le'))
        for invalid in [b'project_id:demo-universal-search', b'tudo-aqui-macacu demo-other',
                        b'tudo-aqui-macacu .searchlocal', b'unknown-project']:
            with self.assertRaises(release.ReleaseError):
                release.validate_resources(invalid)


if __name__ == '__main__':
    unittest.main()
