import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/config/weather_config.dart';
import '../../../core/models/weather_data.dart';
import '../../../core/services/weather_service.dart';
import '../../../core/theme/app_colors.dart';
import 'weather_condition.dart';

class HomeWeatherChip extends StatefulWidget {
  const HomeWeatherChip({
    super.key,
    required this.imageBackground,
    this.service,
  });
  final bool imageBackground;
  final WeatherService? service;
  @override
  State<HomeWeatherChip> createState() => _HomeWeatherChipState();
}

class _HomeWeatherChipState extends State<HomeWeatherChip>
    with WidgetsBindingObserver {
  WeatherData? _data;
  bool _loading = true;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(WeatherConfig.cacheDuration, (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final data = await (widget.service ?? WeatherService.instance).load();
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final condition = data == null ? null : weatherCondition(data.weatherCode);
    final color = widget.imageBackground ? Colors.white : AppColors.ink;
    final age = data == null
        ? Duration.zero
        : DateTime.now().toUtc().difference(data.updatedAt);
    return Container(
      width: 150,
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(
          alpha: widget.imageBackground ? .18 : .78,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.imageBackground
              ? Colors.white.withValues(alpha: .22)
              : AppColors.sky.withValues(alpha: .12),
        ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(WeatherConfig.city),
            const SizedBox(height: 3),
            if (data != null) ...[
              Row(
                children: [
                  Icon(condition!.icon, color: AppColors.yellow, size: 16),
                  const SizedBox(width: 5),
                  Text(
                    '${data.temperature.round()}°C',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Text(condition.description),
              Text(
                'Máx ${data.maximum.round()}° · Mín ${data.minimum.round()}°',
              ),
              if (age >= WeatherConfig.cacheDuration)
                Text('Atualizado há ${age.inMinutes} min'),
            ] else if (_loading)
              Semantics(
                label: 'Carregando previsão',
                child: const SizedBox(
                  height: 30,
                  child: Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              )
            else
              const Text('Previsão indisponível no momento'),
          ],
        ),
      ),
    );
  }
}
