"""Fail-closed release checks. Does not build, sign, upload, or print credentials."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent
APP_ID = 'br.com.tudoaquimacacu.tudo_aqui_macacu'
PROJECT = 'tudo-aqui-macacu'
ANDROID = '{http://schemas.android.com/apk/res/android}'


class ReleaseError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ReleaseError(message)


def fingerprint(value):
    value = value.replace(':', '').strip().upper()
    require(bool(re.fullmatch(r'[A-F0-9]{64}', value)), 'Certificado autorizado ausente/inválido.')
    return value


def preflight(env):
    require(env.get('ANDROID_RELEASE_AUTHORIZED') == 'true', 'Distribuição release não autorizada.')
    fingerprint(env.get('ANDROID_RELEASE_CERT_SHA256', ''))
    if env.get('CI') == 'true':
        require(env.get('GITHUB_EVENT_NAME') == 'workflow_dispatch' and
                env.get('GITHUB_REF') == 'refs/heads/main', 'Release exige solicitação manual na main confiável.')
        require(bool(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', env.get('BUNDLETOOL_VERSION', ''))),
                'Versão aprovada do bundletool ausente.')
        fingerprint(env.get('BUNDLETOOL_SHA256', ''))


def validate_manifest(xml):
    manifest = ET.fromstring(xml)
    require(manifest.get('package') == APP_ID, 'ID oficial inválido ou flavor de teste.')
    application = manifest.find('application')
    require(application is not None, 'Manifesto sem application.')
    require(application.get(ANDROID + 'debuggable', 'false') == 'false', 'Release debuggable recusada.')
    require(manifest.find('instrumentation') is None, 'Artefato de instrumentação recusado.')
    require('SearchLocal' not in xml and 'LocalIsolationVpnService' not in xml and '.searchlocal' not in xml,
            'Componentes searchLocal recusados na distribuição.')


def validate_certificate(output, expected):
    require('android debug' not in output.lower() and 'androiddebugkey' not in output.lower(),
            'Certificado debug recusado.')
    found = re.findall(r'(?:SHA256:|SHA-256 digest:)\s*([a-fA-F0-9:]+)', output)
    require(bool(found) and {fingerprint(v) for v in found} == {fingerprint(expected)},
            'Certificado do artefato diverge da identidade autorizada.')


def forbidden_path(name):
    base = Path(name).name.lower()
    return (base in {'key.properties', '.env'} or base.startswith('.env.') or
            base.endswith(('.jks', '.keystore', '.p12', '.p8', '.pem', '.key')) or
            bool(re.search(r'(service[-_]?account|firebase-adminsdk).*\.json$', base)))


def scan_secret(data):
    return bool(re.search(rb'-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----|"private_key"\s*:', data))


def validate_resources(resources):
    readable = resources + resources.replace(b'\0', b'')
    require(PROJECT.encode() in readable and b'demo-' not in readable and b'.searchlocal' not in readable,
            'Recursos Firebase oficiais ausentes ou configuração de teste detectada.')


def static_checks(root=ROOT):
    gradle = (root / 'android/app/build.gradle.kts').read_text(encoding='utf-8')
    release = re.search(r'\brelease\s*\{([^}]+)', gradle)
    require(release is not None and 'getByName("authorizedRelease")' in release[1] and
            'getByName("debug")' not in release[1] and 'isDebuggable = false' in release[1],
            'Gradle release exige assinatura autorizada e debuggable=false.')
    for guard in ['verifyReleaseAuthorization()', 'gradle.taskGraph.whenReady', 'LOCAL_SEARCH_',
                  'ANDROID_RELEASE_CERT_SHA256', 'certificate.checkValidity()',
                  'actual == expected', 'it.buildType != "debug"', 'GoogleServices']:
        require(guard in gradle, 'Guarda de assinatura/isolamento ausente no Gradle.')
    require('key.properties' not in re.sub(r'//[^\n]*', '', gradle),
            'Gradle não deve carregar credenciais legadas em debug.')
    require(f'applicationId = "{APP_ID}"' in gradle, 'Identidade oficial alterada.')
    config = json.loads((root / 'firebase/android/google-services.json').read_text(encoding='utf-8'))
    require(config['project_info']['project_id'] == PROJECT, 'Configuração Firebase oficial inválida.')
    require(any(c.get('client_info', {}).get('android_client_info', {}).get('package_name') == APP_ID
                for c in config.get('client', [])), 'Firebase não corresponde ao ID oficial.')
    workflow = (root / '.github/workflows/main.yml').read_text(encoding='utf-8')
    codemagic = (root / 'codemagic.yaml').read_text(encoding='utf-8')
    require('text.replace(' not in workflow + codemagic and 'insert_after(' not in codemagic,
            'Workflow não deve reescrever assinatura Gradle.')
    for guard in ['needs: security-tests', 'needs: [security-tests, build]', 'environment: android-release',
                  'github.ref == \'refs/heads/main\'', '--preflight', '--artifact',
                  'app-release-verified', 'BUNDLETOOL_SHA256']:
        require(guard in workflow, 'Guarda obrigatória ausente no workflow.')
    require("if: ${{ github.event_name == 'workflow_dispatch' && inputs.build_type == 'debug-apk' }}" in workflow,
            'Artefatos debug exigem solicitação manual.')
    require('android_signing:' not in codemagic and 'CM_KEYSTORE' not in codemagic,
            'Workflow debug não deve consumir assinatura de distribuição.')
    tracked = subprocess.run(['git', 'ls-files', '-z'], cwd=root, check=True, capture_output=True).stdout
    for name in tracked.decode('utf-8').split('\0'):
        if not name:
            continue
        require(not forbidden_path(name), 'Material de assinatura/credencial rastreado no Git.')
        path = root / name
        if name.startswith(('lib/', 'android/', 'firebase/')) and path.is_file():
            require(not scan_secret(path.read_bytes()), 'Credencial privada embutida nos fontes/configurações.')


def command(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=120)
    require(result.returncode == 0, 'Ferramenta de inspeção recusou o artefato; detalhes sensíveis omitidos.')
    return result.stdout + result.stderr


def inspect_artifact(path, expected, bundletool=None, apksigner=None, apkanalyzer=None):
    require(path.is_file(), 'Artefato ausente.')
    fingerprint(expected)
    if path.suffix == '.aab':
        require(bundletool is not None and bundletool.is_file(), 'Inspeção AAB exige bundletool aprovado.')
        tool_hash = fingerprint(os.environ.get('BUNDLETOOL_SHA256', ''))
        require(hashlib.sha256(bundletool.read_bytes()).hexdigest().upper() == tool_hash,
                'Bundletool diverge do hash autorizado.')
        verified = command(['jarsigner', '-J-Duser.language=en', '-J-Duser.country=US', '-verify', str(path)])
        require('jar verified.' in verified.lower() and 'unsigned entries' not in verified.lower(),
                'AAB não integralmente assinado/verificado.')
        certificate = command(['keytool', '-J-Duser.language=en', '-J-Duser.country=US', '-printcert', '-jarfile', str(path)])
        validate_certificate(certificate, expected)
        manifest = command(['java', '-jar', str(bundletool), 'dump', 'manifest', '--bundle=' + str(path), '--module=base'])
        resource_name = 'base/resources.pb'
    elif path.suffix == '.apk':
        require(bool(apksigner and apkanalyzer), 'Inspeção APK exige apksigner e apkanalyzer do SDK.')
        certificate = command([apksigner, 'verify', '--print-certs', str(path)])
        validate_certificate(certificate, expected)
        manifest = command([apkanalyzer, 'manifest', 'print', str(path)])
        resource_name = 'resources.arsc'
    else:
        raise ValueError('Somente APK/AAB suportados.')
    validate_manifest(manifest)
    with zipfile.ZipFile(path) as archive:
        resources = archive.read(resource_name)
        # Compiled Android resources preserve UTF-8/UTF-16 strings. This is a
        # fail-closed check of packaged configuration, not proof of runtime I/O.
        validate_resources(resources)
        for item in archive.infolist():
            require(not forbidden_path(item.filename), 'Credencial/material de assinatura dentro do artefato.')
            if item.filename.endswith(('.json', '.properties', '.env', '.txt')):
                require(item.file_size <= 2_000_000 and not scan_secret(archive.read(item)),
                        'Credencial privada ou arquivo de configuração excessivo no artefato.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--static', action='store_true')
    modes.add_argument('--preflight', action='store_true')
    modes.add_argument('--artifact', type=Path)
    parser.add_argument('--bundletool', type=Path)
    parser.add_argument('--apksigner')
    parser.add_argument('--apkanalyzer')
    args = parser.parse_args()
    if args.static:
        static_checks()
        print('Verificações estáticas Android/CI aprovadas; nenhum artefato release inspecionado.')
    else:
        preflight(os.environ)
        if args.artifact:
            inspect_artifact(args.artifact, os.environ['ANDROID_RELEASE_CERT_SHA256'],
                             args.bundletool, args.apksigner, args.apkanalyzer)
            print('Artefato verificado; não publicado.')
        else:
            print('Autorização configurada; assinatura/artefato ainda não comprovados.')


if __name__ == '__main__':
    try:
        main()
    except ReleaseError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        # Tools may include paths/credential-related details in their exceptions.
        print('Verificação release recusada. Confira autorização, ferramentas e configuração; nenhum segredo exibido.', file=sys.stderr)
        sys.exit(1)
