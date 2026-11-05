import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/theme/app_colors.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';

void main() {
  testWidgets('shared theme standardizes brand, controls, and form fields', (
    tester,
  ) async {
    final theme = AppTheme.light;
    final filledButtonSize = theme.filledButtonTheme.style!.minimumSize!
        .resolve(const <WidgetState>{})!;
    final outlinedButtonSize = theme.outlinedButtonTheme.style!.minimumSize!
        .resolve(const <WidgetState>{})!;

    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, AppColors.sky);
    expect(theme.colorScheme.secondary, AppColors.orange);
    expect(
      theme.textTheme.bodyMedium?.fontFamily?.startsWith('Poppins'),
      isTrue,
    );
    expect(theme.scaffoldBackgroundColor, AppColors.soft);
    expect(filledButtonSize.height, 48);
    expect(outlinedButtonSize.height, 48);
    expect(theme.inputDecorationTheme.filled, isTrue);
    expect(theme.inputDecorationTheme.fillColor, Colors.white);
    expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    expect(theme.cardTheme.elevation, 1);
    expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
    expect(theme.navigationBarTheme.height, 80);
    expect(theme.navigationBarTheme.backgroundColor, Colors.white);
    expect(theme.navigationBarTheme.indicatorColor, AppColors.skyTint);
    expect(
      theme.navigationBarTheme.labelBehavior,
      NavigationDestinationLabelBehavior.alwaysShow,
    );
    expect(AppTheme.brandGradient.colors, [AppColors.ocean, AppColors.sky]);
    await tester.pumpWidget(MaterialApp(theme: theme, home: const SizedBox()));
    expect(tester.takeException(), isNull);
  });

  test('navigation labels use the shared selected and unselected styles', () {
    final selectedLabel = themeLabelStyle({WidgetState.selected});
    final unselectedLabel = themeLabelStyle({});

    expect(selectedLabel.fontFamily?.startsWith('Poppins'), isTrue);
    expect(selectedLabel.color, AppColors.ocean);
    expect(selectedLabel.fontWeight, FontWeight.w700);
    expect(unselectedLabel.fontFamily?.startsWith('Poppins'), isTrue);
    expect(unselectedLabel.color, AppColors.muted);
    expect(unselectedLabel.fontWeight, FontWeight.w400);
  });

  testWidgets('theme buttons inherit the shared Poppins family', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(
                onPressed: () {},
                child: const Text('Botão preenchido'),
              ),
              OutlinedButton(
                onPressed: () {},
                child: const Text('Botão contornado'),
              ),
              TextButton(onPressed: () {}, child: const Text('Botão de texto')),
            ],
          ),
        ),
      ),
    );

    for (final label in [
      'Botão preenchido',
      'Botão contornado',
      'Botão de texto',
    ]) {
      final effectiveStyle = DefaultTextStyle.of(
        tester.element(find.text(label)),
      ).style;
      expect(effectiveStyle.fontFamily?.startsWith('Poppins'), isTrue);
    }
  });
}

TextStyle themeLabelStyle(Set<WidgetState> states) =>
    AppTheme.light.navigationBarTheme.labelTextStyle!.resolve(states)!;
