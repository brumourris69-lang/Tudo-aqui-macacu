import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tudo_aqui_macacu/core/models/weather_data.dart';
import 'package:tudo_aqui_macacu/core/services/weather_service.dart';

class _EmptyWeatherCache implements WeatherCache {
  @override
  Future<WeatherData?> read() async => null;
  @override
  Future<void> write(WeatherData data) async {}
}

WeatherService unavailableWeather() => WeatherService(
  client: MockClient((_) async => http.Response('', 503)),
  cache: _EmptyWeatherCache(),
);
