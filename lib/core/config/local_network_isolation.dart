import 'dart:io';
import 'package:flutter/services.dart';
import 'local_search_environment.dart';

bool isLocalEmulatorEndpoint(
  Uri uri, {
  int? authPort,
  bool? localAdminBridgeEnabled,
  String? host,
}) =>
    (uri.scheme == 'http' &&
        uri.host == (host ?? LocalSearchEnvironment.host) &&
        [
          authPort ?? LocalSearchEnvironment.authEmulatorPort,
          8087,
          5007,
        ].contains(uri.port) &&
        uri.userInfo.isEmpty) ||
    isLocalAdminBridgeEndpoint(
      uri,
      localSearchEnabled: localAdminBridgeEnabled,
      host: host,
    );

/// Allows only the debug-only admin bridge route on its dedicated reverse
/// port. The Android Emulator uses adb reverse to reach host loopback.
bool isLocalAdminBridgeEndpoint(
  Uri uri, {
  bool? localSearchEnabled,
  String? host,
  int? port,
}) =>
    (localSearchEnabled ?? LocalSearchEnvironment.enabled) &&
    uri.scheme == 'http' &&
    uri.host == (host ?? LocalSearchEnvironment.host) &&
    uri.port == (port ?? LocalSearchEnvironment.adminBridgePort) &&
    uri.path == LocalSearchEnvironment.adminBridgePath &&
    uri.userInfo.isEmpty &&
    !uri.hasQuery &&
    !uri.hasFragment;

Future<void> verifyLocalAuthDiagnosticProxy({
  required bool enabled,
  required String host,
  required int port,
  required Future<void> Function(String host, int port) probe,
}) async {
  if (!enabled) return;
  if (host != '127.0.0.1' || port != 9197) {
    throw StateError('Proxy local de diagnóstico do Auth não autorizado.');
  }
  try {
    await probe(host, port).timeout(const Duration(seconds: 2));
  } catch (_) {
    throw StateError(
      'Proxy local de diagnóstico do Auth indisponível; Firebase não iniciado.',
    );
  }
}

/// Supplements the native per-app VPN, including HTTP images and HTTP clients.
class LocalNetworkIsolation extends HttpOverrides {
  static const channel = MethodChannel('macacu/local-isolation');
  static int blockedConnections = 0;

  static Future<void> prepare() async {
    final native = await channel.invokeMapMethod<String, dynamic>(
      'environment',
    );
    final nativeLocal = native?['local'] == true;
    if (nativeLocal != LocalSearchEnvironment.enabled) {
      throw StateError('Variante Android e flags locais incompatíveis.');
    }
    if (!nativeLocal) return;
    if (LocalSearchEnvironment.host != '127.0.0.1') {
      throw StateError('Esta variante exige loopback e adb reverse.');
    }
    if (native?['isolated'] != true) {
      throw StateError(
        'VPN nativa local obrigatória antes de inicializar Firebase.',
      );
    }
    LocalSearchEnvironment.requireDemo(LocalSearchEnvironment.project);
    await verifyLocalAuthDiagnosticProxy(
      enabled: LocalSearchEnvironment.authHttpDiagnosticsEnabled,
      host: LocalSearchEnvironment.host,
      port: LocalSearchEnvironment.authEmulatorPort,
      probe: (host, port) async {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 2),
        );
        socket.destroy();
      },
    );
    HttpOverrides.global = LocalNetworkIsolation();
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (!isLocalEmulatorEndpoint(uri) || proxyHost != null) {
        blockedConnections++;
        throw StateError('Conexão externa bloqueada no ambiente local.');
      }
      return Socket.startConnect(uri.host, uri.port);
    };
    return client;
  }
}
