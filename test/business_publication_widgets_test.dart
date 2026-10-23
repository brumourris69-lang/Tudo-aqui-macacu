import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_card.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/published_business_list.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/published_business_strip.dart';

const _demo = Business('Demo fixture', 'Comércio', '', '', '', 0);
const _published = Business(
  'Estabelecimento publicado', 'Comércio', '', '', '', 0,
  featured: true,
);

void main() {
  testWidgets('empty published list stays empty and does not show demo fixtures', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublishedBusinessList(
            businessesStreamFactory: () => Stream.value(const <Business>[]),
            saved: const {},
            favorite: (_) {},
            cardBuilder: (_, business, _, _) => Text(business.name),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nenhum estabelecimento publicado por enquanto.'), findsOneWidget);
    expect(find.text(_demo.name), findsNothing);
  });

  testWidgets('published list shows initial error and retries successfully', (
    tester,
  ) async {
    final firstAttempt = StreamController<List<Business>>();
    var attempts = 0;
    Stream<List<Business>> load() => ++attempts == 1
        ? firstAttempt.stream
        : Stream.value(const [_published]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublishedBusinessList(
            businessesStreamFactory: load,
            saved: const {},
            favorite: (_) {},
            cardBuilder: (_, business, _, _) => Text(business.name),
          ),
        ),
      ),
    );
    firstAttempt.addError(StateError('offline'));
    await tester.pump();
    expect(find.text('Tentar novamente'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text(_published.name), findsOneWidget);
    expect(attempts, 2);
    await tester.pumpWidget(const SizedBox());
    unawaited(firstAttempt.close());
  });

  testWidgets('empty featured strip does not show demo establishments', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublishedBusinessStrip(
            businessesStreamFactory: () => Stream.value(const <Business>[]),
            saved: const {},
            favorite: (_) {},
            cardBuilder: (_, business, _, _) => Text(business.name),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nenhum estabelecimento em destaque.'), findsOneWidget);
    expect(find.text(_demo.name), findsNothing);
  });

  testWidgets('featured cards gain vertical room for enlarged text', (
    tester,
  ) async {
    const business = Business(
      'Estabelecimento fictício 01 com nome longo',
      'Comércio',
      'Mercados',
      'Descrição longa para validar o cartão de destaque em fonte ampliada.',
      'Centro, Cachoeiras de Macacu',
      0,
      featured: true,
    );
    await tester.binding.setSurfaceSize(const Size(320, 720));

    for (final textScale in [1.0, 1.5]) {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: PublishedBusinessStrip(
              businessesStreamFactory: () => Stream.value(const [business]),
              saved: const {},
              favorite: (_) {},
              cardBuilder: (context, business, saved, onFavorite) =>
                  BusinessCard(
                    business: business,
                    saved: saved,
                    onFavorite: onFavorite,
                    onOpen: () {},
                    onViewBusiness: () {},
                    onWhatsApp: () {},
                    compact: true,
                  ),
            ),
          ),
        ),
      );
      await tester.pump();

      final list = tester.widget<ListView>(find.byType(ListView));
      expect(
        tester.getSize(find.byWidget(list)).height,
        textScale == 1.0 ? 230 : greaterThan(230),
      );
      expect(tester.takeException(), isNull, reason: 'text scale $textScale');
    }

    await tester.binding.setSurfaceSize(null);
  });
}
