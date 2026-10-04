abstract final class WeatherConfig {
  static const city = 'Cachoeiras de Macacu · RJ';
  // Open-Meteo geocoding / GeoNames 3468425: municipal seat, RJ, Brazil.
  static const latitude = -22.4625;
  static const longitude = -42.65306;
  static const timezone = 'America/Sao_Paulo';
  static const cacheDuration = Duration(minutes: 30);
  static const timeout = Duration(seconds: 10);
  static const cacheKey = 'weather_macacu_v1';

  static Uri get endpoint => Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': '$latitude',
    'longitude': '$longitude',
    'timezone': timezone,
    'forecast_days': '1',
    'temperature_unit': 'celsius',
    'wind_speed_unit': 'kmh',
    'precipitation_unit': 'mm',
    'current':
        'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m',
    'daily':
        'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
  });
}
