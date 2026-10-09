import 'dart:io';
import 'package:flutter/services.dart';
import 'local_search_environment.dart';

bool isLocalEmulatorEndpoint(Uri uri) =>
    uri.scheme == 'http' &&
    uri.host == LocalSearchEnvironment.host &&
    [9097, 8087, 5007].contains(uri.port) &&
    uri.userInfo.isEmpty;

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
