import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/search/pages/universal_search_page.dart';
import 'package:tudo_aqui_macacu/features/search/widgets/universal_search_bar.dart';

void main() {
  testWidgets(
    'search button opens interface, focuses, selects filters, clears and returns',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => UniversalSearchBar(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const UniversalSearchPage(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(UniversalSearchBar));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(
        find.text('Encontre tudo em Cachoeiras de Macacu.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Serviços'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Serviços'))
            .selected,
        isTrue,
      );
      await tester.enterText(find.byType(TextField), 'padaria');
      await tester.pumpAndSettle();
      expect(find.text('Pesquisa em desenvolvimento'), findsOneWidget);
      await tester.tap(find.byTooltip('Limpar pesquisa'));
      await tester.pumpAndSettle();
      expect(
        find.text('Encontre tudo em Cachoeiras de Macacu.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(UniversalSearchBar), findsOneWidget);
      expect(find.byType(UniversalSearchPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small screen and landscape scroll with keyboard and enlarged text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      for (final size in [const Size(320, 568), const Size(700, 420)]) {
        tester.view.physicalSize = size;
        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const UniversalSearchPage(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(ChoiceChip, 'Utilidades'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Utilidades'));
        await tester.pump();
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Utilidades'))
              .selected,
          isTrue,
        );
        await tester.enterText(find.byType(TextField), 'água');
        await tester.pumpAndSettle();
        expect(find.text('Pesquisa em desenvolvimento'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
