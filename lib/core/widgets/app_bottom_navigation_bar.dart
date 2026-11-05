import 'package:flutter/material.dart';
import 'package:tudo_aqui_macacu/core/theme/app_colors.dart';

/// Primary app navigation. Destination order and labels are part of the
/// established product structure; styling comes from the app theme.
class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Início',
    ),
    NavigationDestination(
      icon: Icon(Icons.grid_view_outlined),
      selectedIcon: Icon(Icons.grid_view_rounded),
      label: 'Explorar',
    ),
    NavigationDestination(
      icon: Icon(Icons.public_outlined),
      selectedIcon: Icon(Icons.public_rounded),
      label: 'Utilidades',
    ),
    NavigationDestination(
      icon: Icon(Icons.favorite_border_rounded),
      selectedIcon: Icon(Icons.favorite_rounded),
      label: 'Favoritos',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: 'Perfil',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context).navigationBarTheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final height = textScale >= 1.3 ? 96.0 : (baseTheme.height ?? 80.0);
    final width = MediaQuery.sizeOf(context).width;
    final labelSize = textScale >= 1.3
        ? (width < 360
              ? 7.5
              : width < 400
              ? 8.2
              : 9.5)
        : 10.0;
    final labelStyle = WidgetStateProperty.resolveWith<TextStyle>((states) {
      final style = baseTheme.labelTextStyle?.resolve(states);
      return (style ?? Theme.of(context).textTheme.labelMedium!).copyWith(
        fontSize: labelSize,
        color: states.contains(WidgetState.selected)
            ? AppColors.ocean
            : AppColors.muted,
      );
    });
    return NavigationBarTheme(
      data: baseTheme.copyWith(height: height, labelTextStyle: labelStyle),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
      ),
    );
  }
}
