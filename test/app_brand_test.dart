import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/theme/app_colors.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/core/widgets/app_brand.dart';

void main() {
  testWidgets('renders the original local logo and brand tagline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: AppBrand()),
      ),
    );

    expect(find.byKey(const ValueKey('app-brand-logo-local')), findsOneWidget);
    expect(find.byIcon(Icons.location_on_rounded), findsNothing);
    expect(find.text('Tudo Aqui'), findsOneWidget);
    expect(find.text('Macacu'), findsOneWidget);
    expect(find.text('A cidade na sua mão.'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.text('Tudo Aqui'))
          .style
          ?.fontFamily
          ?.startsWith('Poppins'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports inverse and compact brand variants', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppBrand(inverse: true),
              AppBrand(compact: true, tagline: ''),
            ],
          ),
        ),
      ),
    );

    final tudoAqui = tester.widgetList<Text>(find.text('Tudo Aqui')).toList();
    final macacu = tester.widgetList<Text>(find.text('Macacu')).toList();
    expect(tudoAqui.first.style?.color, Colors.white);
    expect(macacu, hasLength(2));
    expect(macacu.first.style?.color, AppColors.orange);
    expect(macacu.last.style?.color, AppColors.ocean);
    expect(find.text('A cidade na sua mão.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the local logo when a remote logo cannot load', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppBrand(logoUrl: 'https://invalid.example/logo.png'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-brand-logo-local')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a narrow header at enlarged text scale', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: const AppBrand(compact: true),
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.share)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.favorite)),
            ],
          ),
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: const Center(child: AppBrand(compact: true)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
