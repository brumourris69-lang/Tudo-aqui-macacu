import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tudo_aqui_macacu/core/models/weather_data.dart';
import 'package:tudo_aqui_macacu/core/services/weather_service.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';
import 'package:tudo_aqui_macacu/features/home/widgets/home_weather_chip.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

class _Cache implements WeatherCache {
  @override
  Future<WeatherData?> read() async => null;
  @override
  Future<void> write(WeatherData data) async {}
}

const _title =
    'Encontre serviços, lazer e oportunidades em Cachoeiras de Macacu';
Map<String, dynamic> _weather() => {
  'current': {
    'temperature_2m': 23.4,
    'apparent_temperature': 24.1,
    'relative_humidity_2m': 80,
    'precipitation': .3,
    'weather_code': 1,
    'wind_speed_10m': 9.2,
  },
  'daily': {
    'temperature_2m_max': [28.1],
    'temperature_2m_min': [18.2],
    'precipitation_probability_max': [70],
    'weather_code': [1],
  },
};

void main() {
  testWidgets('hero editing actions remain usable with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var edits = 0;
    var visuals = 0;
    var titles = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: WelcomeHero(
                config: HomePageConfig.fromMap({'heroTitle': _title}),
                user: null,
                weatherService: WeatherService(
                  client: MockClient((_) async => http.Response('', 503)),
                  cache: _Cache(),
                ),
                onSearch: () {},
                editMode: true,
                onEditHero: () => edits++,
                onEditVisual: () => visuals++,
                onEditTitle: () => titles++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Textos'));
    await tester.tap(find.text('Visual'));
    await tester.tap(find.text('Toque para editar'));
    expect(edits, 1);
    expect(visuals, 1);
    expect(titles, 1);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [320.0, 360.0, 393.0, 480.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final state in ['loading', 'available', 'unavailable']) {
        testWidgets('hero $width text $scale weather $state remains usable', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final pending = Completer<http.Response>();
          final weather = WeatherService(
            client: MockClient((_) => pending.future),
            cache: _Cache(),
          );
          var searches = 0;
          var profiles = 0;
          final config = HomePageConfig.fromMap({
            'heroTitle': _title,
            'searchPlaceholder': 'Buscar serviços locais',
            'visual': {
              'backgroundType': 'gradient',
              'location': 'Cachoeiras de Macacu · RJ',
              'slogan': 'A cidade na sua mão.',
              'greeting': 'A cidade na sua mão.',
            },
            'sectionOrder': ['categories', 'banner'],
            'sections': {'banner': false},
            'sectionLimits': {'categories': 4},
          });
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1400),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: WelcomeHero(
                      config: config,
                      user: null,
                      weatherService: weather,
                      onSearch: () => searches++,
                      onProfile: () => profiles++,
                    ),
                  ),
                ),
              ),
            ),
          );
          if (state != 'loading') {
            pending.complete(
              state == 'available'
                  ? http.Response(jsonEncode(_weather()), 200)
                  : http.Response('', 503),
            );
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          final title = tester.renderObject<RenderParagraph>(find.text(_title));
          expect(
            title.didExceedMaxLines,
            isFalse,
            reason: 'Administrative title must not be truncated',
          );
          expect(
            find.textContaining('Cachoeiras de Macacu', findRichText: true),
            findsNWidgets(2),
            reason: 'Title plus one location, not a repeated weather location',
          );
          if (state == 'loading') {
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            expect(
              find.bySemanticsLabel('Carregando previsão'),
              findsOneWidget,
            );
          } else if (state == 'available') {
            expect(find.text('23°C'), findsOneWidget);
            expect(find.text('Predominantemente limpo'), findsOneWidget);
          } else {
            expect(find.textContaining('indisponível'), findsOneWidget);
            expect(
              tester.getSize(find.byType(HomeWeatherChip)).height,
              lessThan(96),
            );
          }
          expect(find.byTooltip('Notificações'), findsOneWidget);
          await tester.tap(find.text('Buscar serviços locais'));
          await tester.tap(find.byTooltip('Perfil'));
          expect(searches, 1);
          expect(profiles, 1);
          expect(config.order, ['categories', 'banner']);
          expect(config.enabled('banner'), isFalse);
          expect(config.limitFor('categories'), 4);
          if (!pending.isCompleted) {
            pending.complete(http.Response('', 503));
            await tester.pumpAndSettle();
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
