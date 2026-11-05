import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/theme/app_colors.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_info_block.dart';

void main() {
  testWidgets('InfoBlock exibe título e texto com estilo básico preservado', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: const InfoBlock(title: 'Sobre', text: 'Texto local'),
        ),
      ),
    );

    expect(find.text('Sobre'), findsOneWidget);
    expect(find.text('Texto local'), findsOneWidget);

    final title = tester.widget<Text>(find.text('Sobre'));
    expect(title.style?.fontSize, 14);
    expect(title.style?.fontWeight, FontWeight.w700);

    final body = tester.widget<Text>(find.text('Texto local'));
    expect(body.style?.color, AppColors.muted);
    expect(body.style?.height, 1.45);
  });
}
