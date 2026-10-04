class WeatherData {
  const WeatherData({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.precipitation,
    required this.weatherCode,
    required this.windSpeed,
    required this.maximum,
    required this.minimum,
    required this.rainChance,
    required this.dailyWeatherCode,
    required this.updatedAt,
  });

  final double temperature,
      feelsLike,
      humidity,
      precipitation,
      windSpeed,
      maximum,
      minimum,
      rainChance;
  final int weatherCode, dailyWeatherCode;

  /// Time this response was successfully obtained, stored in UTC.
  final DateTime updatedAt;

  factory WeatherData.fromJson(Map<String, dynamic> json, DateTime updatedAt) {
    final current = json['current'];
    final daily = json['daily'];
    if (current is! Map || daily is! Map) {
      throw const FormatException('Previsão inválida');
    }
    double number(dynamic value) {
      if (value is! num || !value.isFinite) {
        throw const FormatException('Valor meteorológico inválido');
      }
      return value.toDouble();
    }

    double first(String key) {
      final values = daily[key];
      if (values is! List || values.isEmpty) {
        throw const FormatException('Previsão diária ausente');
      }
      return number(values.first);
    }

    int code(double value) {
      if (value != value.roundToDouble() || value < 0 || value > 99) {
        throw const FormatException('Código meteorológico inválido');
      }
      return value.toInt();
    }

    final data = WeatherData(
      temperature: number(current['temperature_2m']),
      feelsLike: number(current['apparent_temperature']),
      humidity: number(current['relative_humidity_2m']),
      precipitation: number(current['precipitation']),
      weatherCode: code(number(current['weather_code'])),
      windSpeed: number(current['wind_speed_10m']),
      maximum: first('temperature_2m_max'),
      minimum: first('temperature_2m_min'),
      rainChance: first('precipitation_probability_max'),
      dailyWeatherCode: code(first('weather_code')),
      updatedAt: updatedAt.toUtc(),
    );
    if (data.minimum > data.maximum ||
        data.humidity < 0 ||
        data.humidity > 100 ||
        data.rainChance < 0 ||
        data.rainChance > 100 ||
        data.precipitation < 0 ||
        data.windSpeed < 0) {
      throw const FormatException('Previsão inconsistente');
    }
    return data;
  }

  Map<String, dynamic> toJson() => {
    'current': {
      'temperature_2m': temperature,
      'apparent_temperature': feelsLike,
      'relative_humidity_2m': humidity,
      'precipitation': precipitation,
      'weather_code': weatherCode,
      'wind_speed_10m': windSpeed,
    },
    'daily': {
      'temperature_2m_max': [maximum],
      'temperature_2m_min': [minimum],
      'precipitation_probability_max': [rainChance],
      'weather_code': [dailyWeatherCode],
    },
    'updatedAt': updatedAt.toIso8601String(),
  };
}
