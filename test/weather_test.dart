import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tudo_aqui_macacu/core/config/weather_config.dart';
import 'package:tudo_aqui_macacu/core/models/weather_data.dart';
import 'package:tudo_aqui_macacu/core/services/weather_service.dart';
import 'package:tudo_aqui_macacu/features/home/widgets/home_weather_chip.dart';
import 'package:tudo_aqui_macacu/features/home/widgets/weather_condition.dart';

final date = DateTime.utc(2026, 10, 4, 15);
Map<String, dynamic> response() => {
  'current': <String, dynamic>{
    'temperature_2m': 23.4,
    'apparent_temperature': 24.1,
    'relative_humidity_2m': 80,
    'precipitation': 0.3,
    'weather_code': 61,
    'wind_speed_10m': 9.2,
  },
  'daily': <String, dynamic>{
    'temperature_2m_max': [28.1],
    'temperature_2m_min': [18.2],
    'precipitation_probability_max': [70],
    'weather_code': [80],
  },
};

class MemoryCache implements WeatherCache {
  MemoryCache([this.data]);
  WeatherData? data;
  @override
  Future<WeatherData?> read() async => data;
  @override
  Future<void> write(WeatherData value) async => data = value;
}

WeatherService service(http.Client client, [WeatherCache? cache]) =>
    WeatherService(
      client: client,
      cache: cache ?? MemoryCache(),
      now: () => date,
    );

void main() {
  testWidgets('request timeout produces safe unavailable state', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeWeatherChip(
          imageBackground: false,
          service: service(MockClient((_) => pending.future)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(WeatherConfig.timeout + const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Previsão indisponível no momento'), findsOneWidget);
    pending.complete(http.Response('', 503));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('offline stale cache displays last values and age', (
    tester,
  ) async {
    final cached = WeatherData.fromJson(
      response(),
      DateTime.now().toUtc().subtract(const Duration(hours: 2)),
    );
    final weather = WeatherService(
      client: MockClient((_) async => http.Response('', 503)),
      cache: MemoryCache(cached),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeWeatherChip(imageBackground: false, service: weather),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('23°C'), findsOneWidget);
    expect(find.textContaining('Atualizado há'), findsOneWidget);
    expect(find.text('Previsão indisponível no momento'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  test('parses current, daily and update time without invented values', () {
    final data = WeatherData.fromJson(response(), date);
    expect(data.temperature, 23.4);
    expect(data.feelsLike, 24.1);
    expect(data.humidity, 80);
    expect(data.precipitation, .3);
    expect(data.windSpeed, 9.2);
    expect(data.maximum, 28.1);
    expect(data.minimum, 18.2);
    expect(data.rainChance, 70);
    expect(data.weatherCode, 61);
    expect(data.dailyWeatherCode, 80);
    expect(data.updatedAt, date);
  });
  test('friendly Portuguese WMO mapping and unknown fallback', () {
    expect(weatherCondition(0).description, 'Céu limpo');
    expect(weatherCondition(61).description, 'Chuva');
    expect(weatherCondition(95).icon, Icons.thunderstorm_rounded);
    expect(weatherCondition(10).description, 'Condição indisponível');
    for (final code in [
      0,
      1,
      2,
      3,
      45,
      48,
      51,
      53,
      55,
      56,
      57,
      61,
      63,
      65,
      66,
      67,
      71,
      73,
      75,
      77,
      80,
      81,
      82,
      85,
      86,
      95,
      96,
      99,
    ]) {
      expect(
        weatherCondition(code).description,
        isNot('Condição indisponível'),
      );
    }
  });
  test('rejects missing, null, inconsistent and non-finite weather', () {
    expect(() => WeatherData.fromJson({}, date), throwsFormatException);
    final json = response();
    json['current']['temperature_2m'] = null;
    expect(() => WeatherData.fromJson(json, date), throwsFormatException);
    json['current']['temperature_2m'] = double.nan;
    expect(() => WeatherData.fromJson(json, date), throwsFormatException);
    final other = response();
    other['daily']['temperature_2m_max'] = [0];
    expect(() => WeatherData.fromJson(other, date), throwsFormatException);
  });
  test(
    'request is fixed to Cachoeiras de Macacu RJ and correct units/timezone',
    () async {
      await service(
        MockClient((request) async {
          expect(request.url.host, 'api.open-meteo.com');
          expect(request.url.queryParameters['latitude'], '-22.4625');
          expect(request.url.queryParameters['longitude'], '-42.65306');
          expect(request.url.queryParameters['timezone'], 'America/Sao_Paulo');
          expect(request.url.queryParameters['temperature_unit'], 'celsius');
          expect(
            request.url.queryParameters['daily'],
            contains('temperature_2m_min'),
          );
          return http.Response(jsonEncode(response()), 200);
        }),
      ).load();
    },
  );
  test('HTTP failure is unavailable without cache', () async {
    await expectLater(
      service(MockClient((_) async => http.Response('', 500))).load(),
      throwsA(isA<WeatherUnavailable>()),
    );
  });
  test('invalid JSON is unavailable without cache', () async {
    await expectLater(
      service(MockClient((_) async => http.Response('bad', 200))).load(),
      throwsA(isA<WeatherUnavailable>()),
    );
  });
  test('network failure is unavailable without cache', () async {
    await expectLater(
      service(
        MockClient((_) async => throw http.ClientException('offline')),
      ).load(),
      throwsA(isA<WeatherUnavailable>()),
    );
  });
  test('valid cache skips network', () async {
    final cached = WeatherData.fromJson(
      response(),
      date.subtract(const Duration(minutes: 29)),
    );
    expect(
      await service(
        MockClient((_) async => throw StateError('must not request')),
        MemoryCache(cached),
      ).load(),
      same(cached),
    );
  });
  test('expired cache is refreshed and saved', () async {
    final cache = MemoryCache(
      WeatherData.fromJson(
        response(),
        date.subtract(const Duration(minutes: 30)),
      ),
    );
    final data = await service(
      MockClient((_) async => http.Response(jsonEncode(response()), 200)),
      cache,
    ).load();
    expect(data.updatedAt, date);
    expect(cache.data, same(data));
  });
  test('failed refresh keeps expired valid cache', () async {
    final cached = WeatherData.fromJson(
      response(),
      date.subtract(const Duration(hours: 2)),
    );
    expect(
      await service(
        MockClient((_) async => http.Response('', 503)),
        MemoryCache(cached),
      ).load(),
      same(cached),
    );
  });
  test('concurrent loads and subsequent fresh loads reuse request', () async {
    var calls = 0;
    final weather = service(
      MockClient((_) async {
        calls++;
        return http.Response(jsonEncode(response()), 200);
      }),
    );
    await Future.wait([weather.load(), weather.load()]);
    await weather.load();
    expect(calls, 1);
  });
  test('persistent cache survives another service instance', () async {
    SharedPreferences.setMockInitialValues({});
    await service(
      MockClient((_) async => http.Response(jsonEncode(response()), 200)),
      LocalWeatherCache(),
    ).load();
    final restored = await service(
      MockClient((_) async => throw StateError('no network')),
      LocalWeatherCache(),
    ).load();
    expect(restored.temperature, 23.4);
    expect(restored.updatedAt, date);
  });
  test('corrupt local cache does not prevent successful request', () async {
    SharedPreferences.setMockInitialValues({WeatherConfig.cacheKey: 'bad'});
    expect(
      (await service(
        MockClient((_) async => http.Response(jsonEncode(response()), 200)),
        LocalWeatherCache(),
      ).load()).temperature,
      23.4,
    );
  });
  testWidgets('loading has no fictional temperature', (tester) async {
    final pending = Completer<http.Response>();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeWeatherChip(
          imageBackground: false,
          service: service(MockClient((_) => pending.future)),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('°'), findsNothing);
    expect(find.text(WeatherConfig.city), findsOneWidget);
    pending.complete(http.Response('', 503));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failure is discreet and leaves Home usable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            const Text('Home'),
            HomeWeatherChip(
              imageBackground: true,
              service: service(MockClient((_) async => http.Response('', 500))),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Previsão indisponível no momento'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('real values render and long description fits small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final json = response();
    json['current']['weather_code'] = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeWeatherChip(
            imageBackground: false,
            service: service(
              MockClient((_) async => http.Response(jsonEncode(json), 200)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('23°C'), findsOneWidget);
    expect(find.text('Máx 28° · Mín 18°'), findsOneWidget);
    expect(find.text('Predominantemente limpo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
