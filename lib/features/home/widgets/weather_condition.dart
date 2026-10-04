import 'package:flutter/material.dart';

({String description, IconData icon}) weatherCondition(
  int code,
) => switch (code) {
  0 => (description: 'Céu limpo', icon: Icons.wb_sunny_rounded),
  1 => (description: 'Predominantemente limpo', icon: Icons.wb_sunny_outlined),
  2 => (description: 'Parcialmente nublado', icon: Icons.cloud_queue_rounded),
  3 => (description: 'Nublado', icon: Icons.cloud_rounded),
  45 || 48 => (description: 'Nevoeiro', icon: Icons.foggy),
  51 || 53 || 55 => (description: 'Garoa', icon: Icons.grain_rounded),
  56 || 57 => (description: 'Garoa congelante', icon: Icons.ac_unit_rounded),
  61 || 63 || 65 => (description: 'Chuva', icon: Icons.water_drop_rounded),
  66 || 67 => (description: 'Chuva congelante', icon: Icons.ac_unit_rounded),
  71 ||
  73 ||
  75 ||
  77 ||
  85 ||
  86 => (description: 'Neve', icon: Icons.ac_unit_rounded),
  80 ||
  81 ||
  82 => (description: 'Pancadas de chuva', icon: Icons.water_drop_rounded),
  95 ||
  96 ||
  99 => (description: 'Trovoadas', icon: Icons.thunderstorm_rounded),
  _ => (description: 'Condição indisponível', icon: Icons.cloud_outlined),
};
