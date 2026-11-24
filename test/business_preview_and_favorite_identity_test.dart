import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/premium_projection_result.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/repositories/business_repository.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/public_business_preview.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/published_business_list.dart';

void main() {
  testWidgets(
    'public preview enriches an already-loaded card with Premium cover',
    (tester) async {
      final basic = Business.fromBasicProjection('business-a', const {
        'name': 'Loja A',
        'category': 'Comércio',
        'address': 'Centro',
      });
      final repository = BusinessRepository(
        premiumProjectionLoader: (_) async => PremiumProjectionResult.available(
          premiumUntil: DateTime.now().toUtc().add(const Duration(days: 10)),
          data: const {'imageUrl': 'https://images.example/cover.jpg'},
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PublicBusinessPreview(
            business: basic,
            repository: repository,
            builder: (_, business) => Text(
              business.displayImageUrls.isEmpty
                  ? 'sem capa'
                  : business.displayImageUrls.first,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('https://images.example/cover.jpg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('same-name listings use their stable favorite IDs', (
    tester,
  ) async {
    final first = Business(
      'Mais Bonita',
      'Beleza',
      '',
      '',
      'Centro',
      0,
      id: 'mais-bonita-a',
    );
    final second = Business(
      'Mais Bonita',
      'Beleza',
      '',
      '',
      'Centro',
      0,
      id: 'mais-bonita-b',
    );
    final repository = BusinessRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: PublishedBusinessList(
          repository: repository,
          businessesStreamFactory: () => Stream.value([first, second]),
          saved: const {'mais-bonita-a', 'Mais Bonita'},
          favorite: (_) {},
          cardBuilder: (_, business, saved, _) =>
              Text('${business.id}:${saved ? 'saved' : 'not-saved'}'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('mais-bonita-a:saved'), findsOneWidget);
    expect(find.text('mais-bonita-b:not-saved'), findsOneWidget);
  });
}
