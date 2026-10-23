import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

// ignore: subtype_of_sealed_class
class _DocumentReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PublicContentSnapshot _offers(List<Map<String, dynamic>> values) =>
    PublicContentSnapshot([
      for (var index = 0; index < values.length; index++)
        PublicContentDocument(
          'offer-$index',
          values[index],
          _DocumentReference(),
        ),
    ]);

const _businesses = <Business>[
  Business('Mercado fictício', 'Comércio', '', 'Mercado', 'Centro', 0),
  Business('Café fictício', 'Onde comer?', '', 'Café', 'Centro', 1),
];

void main() {
  testWidgets('featured See all opens the all-establishments directory', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExploreView(
          saved: const {},
          favorite: (_) {},
          businessesStreamFactory: () => Stream.value(_businesses),
        ),
      ),
    );
    await tester.pump();
    final seeAll = find.textContaining('Ver todos');
    await tester.scrollUntilVisible(
      seeAll,
      350,
      scrollable: find
          .descendant(
            of: find.byType(ExploreView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(seeAll);
    await tester.pumpAndSettle();

    expect(find.byType(DirectoryView), findsOneWidget);
    expect(find.text('Estabelecimentos'), findsNWidgets(2));
    expect(find.text('Mercado fictício'), findsOneWidget);
    expect(find.text('Café fictício'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ExploreView), findsOneWidget);
  });

  testWidgets('offers backend failure is not presented as an empty list', (
    tester,
  ) async {
    var attempts = 0;
    Stream<PublicContentSnapshot> loadOffers() => ++attempts == 1
        ? Stream.error(StateError('fixture failure'))
        : Stream.value(
            _offers([
              {'title': 'Oferta fictícia', 'published': true, 'active': true},
            ]),
          );

    await tester.pumpWidget(
      MaterialApp(home: OffersView(streamFactory: loadOffers)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar as ofertas.'), findsOneWidget);
    expect(find.text('Não há ofertas publicadas no momento.'), findsNothing);
    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Oferta fictícia'), findsOneWidget);
    expect(find.text('Não foi possível carregar as ofertas.'), findsNothing);
  });

  testWidgets('successful empty offers response keeps the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OffersView(streamFactory: () => Stream.value(_offers([]))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Não há ofertas publicadas no momento.'), findsOneWidget);
    expect(find.text('Não foi possível carregar as ofertas.'), findsNothing);
    expect(find.text('Tentar novamente'), findsNothing);
  });

  testWidgets(
    'empty contact message gives validation feedback without sending',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ContactView()));
      await tester.tap(find.text('Enviar mensagem'));
      await tester.pump();

      expect(find.text('Digite sua mensagem antes de enviar.'), findsOneWidget);
      expect(find.text('Enviando...'), findsNothing);
    },
  );
}
