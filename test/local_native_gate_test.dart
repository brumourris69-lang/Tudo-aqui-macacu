@Tags(['search-local'])
library;

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/local_network_isolation.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';
import 'package:tudo_aqui_macacu/core/media/media_selection.dart';
import 'package:tudo_aqui_macacu/core/media/media_upload_service.dart';
import 'package:tudo_aqui_macacu/core/services/weather_service.dart';
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  void native(Map<String, Object> value) {
    messenger.setMockMethodCallHandler(
      LocalNetworkIsolation.channel,
      (_) async => value,
    );
  }

  tearDown(() {
    HttpOverrides.global = null;
    messenger.setMockMethodCallHandler(LocalNetworkIsolation.channel, null);
  });
  test('local test build uses the exact demo and loopback', () {
    expect(LocalSearchEnvironment.enabled, isTrue);
    expect(LocalSearchEnvironment.project, 'demo-universal-search');
    expect(LocalSearchEnvironment.host, '127.0.0.1');
  });
  test('local weather never invokes the external HTTP client', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      throw StateError('External weather must not run');
    });
    await expectLater(
      WeatherService(client: client).load(),
      throwsA(isA<WeatherUnavailable>()),
    );
    expect(requests, 0);
    client.close();
  });
  test(
    'local Worker upload refuses before reading token or constructing HTTP client',
    () async {
      var calls = 0;
      final service = WorkerImageUploadService(
        tokenReader: () async {
          calls++;
          throw StateError('Token must not be read');
        },
        clientFactory: () {
          calls++;
          throw StateError('Client must not be created');
        },
      );
      final selection = MediaSelection.local(
        Uint8List(8),
        fileName: 'local.png',
      );
      await expectLater(service.upload(selection), throwsFormatException);
      expect(calls, 0);
    },
  );
  test('local Firebase upload never invokes the backend callable', () async {
    var calls = 0;
    final service = FirebaseImageUploadService(
      callable: (_) async {
        calls++;
        throw StateError('Upload callable must not run');
      },
    );
    final selection = MediaSelection.local(Uint8List(8), fileName: 'local.png');
    await expectLater(service.upload(selection), throwsFormatException);
    expect(calls, 0);
  });
  test('production Android variant refuses local flags', () async {
    native({'local': false, 'isolated': false});
    await expectLater(LocalNetworkIsolation.prepare(), throwsStateError);
  });
  test('local Android refuses startup without its native VPN', () async {
    native({'local': true, 'isolated': false});
    await expectLater(LocalNetworkIsolation.prepare(), throwsStateError);
  });
  test('missing native implementation refuses startup', () async {
    await expectLater(
      LocalNetworkIsolation.prepare(),
      throwsA(isA<MissingPluginException>()),
    );
  });
  test(
    'verified native local isolation installs the HTTP deny policy',
    () async {
      native({'local': true, 'isolated': true});
      await LocalNetworkIsolation.prepare();
      expect(HttpOverrides.current, isA<LocalNetworkIsolation>());
    },
  );
}
