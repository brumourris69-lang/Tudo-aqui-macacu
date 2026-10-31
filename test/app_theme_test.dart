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
    expect(theme.scaffoldBackgroundColor, AppColors.soft);
    expect(filledButtonSize.height, 48);
    expect(outlinedButtonSize.height, 48);
    expect(theme.inputDecorationTheme.filled, isTrue);
    expect(theme.inputDecorationTheme.fillColor, Colors.white);
    expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    await tester.pumpWidget(MaterialApp(theme: theme, home: const SizedBox()));
    expect(tester.takeException(), isNull);
  });
}
