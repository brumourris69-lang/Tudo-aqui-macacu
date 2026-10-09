import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/weather_config.dart';
import '../config/local_search_environment.dart';
import '../models/weather_data.dart';

abstract interface class WeatherCache {
  Future<WeatherData?> read();
  Future<void> write(WeatherData data);
}

class LocalWeatherCache implements WeatherCache {
  @override
  Future<WeatherData?> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      WeatherConfig.cacheKey,
    );
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return WeatherData.fromJson(
      json,
      DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  Future<void> write(WeatherData data) async {
    await (await SharedPreferences.getInstance()).setString(
      WeatherConfig.cacheKey,
      jsonEncode(data.toJson()),
    );
  }
}

class WeatherUnavailable implements Exception {
  const WeatherUnavailable();
}

class WeatherService {
  WeatherService({
    http.Client? client,
    WeatherCache? cache,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _cache = cache ?? LocalWeatherCache(),
       _now = now ?? DateTime.now;
  static final instance = WeatherService();
  final http.Client _client;
  final WeatherCache _cache;
  final DateTime Function() _now;
  WeatherData? _last;
  Future<WeatherData>? _pending;
  bool _cacheRead = false;

  Future<WeatherData> load() =>
      _pending ??= _load().whenComplete(() => _pending = null);

  Future<WeatherData> _load() async {
    if (LocalSearchEnvironment.enabled) throw const WeatherUnavailable();
    if (!_cacheRead) {
      _cacheRead = true;
      try {
        _last = await _cache.read().timeout(WeatherConfig.timeout);
      } catch (_) {
        /* Ignore corrupt/unavailable storage. */
      }
    }
    final previous = _last;
    final age = previous == null
        ? null
        : _now().toUtc().difference(previous.updatedAt);
    if (age != null && !age.isNegative && age < WeatherConfig.cacheDuration) {
      return previous!;
    }
    try {
      final response = await _client
          .get(WeatherConfig.endpoint)
          .timeout(WeatherConfig.timeout);
      if (response.statusCode != 200) throw const WeatherUnavailable();
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Previsão inválida');
      }
      final data = WeatherData.fromJson(json, _now());
      _last = data;
      try {
        await _cache.write(data).timeout(WeatherConfig.timeout);
      } catch (_) {
        /* Keep valid data in memory. */
      }
      return data;
    } catch (_) {
      if (previous != null) return previous;
      throw const WeatherUnavailable();
    }
  }
}
