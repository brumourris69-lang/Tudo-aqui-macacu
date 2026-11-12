import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/premium_projection_result.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/repositories/business_repository.dart';
import 'package:tudo_aqui_macacu/features/businesses/screens/business_profile.dart';

void main() {
  final basic = Business.fromBasicProjection('basic-1', const {
    'name': 'Mercearia da Praça',
    'category': 'Comércio',
    'subcategory': 'Mercado',
    'address': 'Praça Central, Cachoeiras de Macacu',
    'phone': '(21) 2222-3333',
  });

  testWidgets('Premium ativo enriquece somente o perfil selecionado', (
    tester,
  ) async {
    final requestedIds = <String>[];
    final repository = BusinessRepository(
      premiumProjectionLoader: (id) async {
        requestedIds.add(id);
        return PremiumProjectionResult.available(
          premiumUntil: DateTime.now().toUtc().add(const Duration(days: 2)),
          data: const {
            'description': 'Produtos artesanais e atendimento completo.',
            'whatsapp': '5521999999999',
            'hours': 'Seg a sex: 09:00 às 18:00',
          },
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PublicBusinessProfile(
          business: basic,
          saved: false,
          onFavorite: () {},
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedIds, ['basic-1']);
    expect(
      find.text('Produtos artesanais e atendimento completo.'),
      findsOneWidget,
    );
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Praça Central, Cachoeiras de Macacu'), findsOneWidget);
    expect(find.text('(21) 2222-3333'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final status in [
    PremiumProjectionStatus.missing,
    PremiumProjectionStatus.expired,
    PremiumProjectionStatus.permissionDenied,
    PremiumProjectionStatus.unavailable,
    PremiumProjectionStatus.invalid,
  ]) {
    testWidgets('Premium $status mantém a ficha Básica sem erro visível', (
      tester,
    ) async {
      final repository = BusinessRepository(
        premiumProjectionLoader: (_) async =>
            PremiumProjectionResult(status: status),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PublicBusinessProfile(
            business: basic,
            saved: false,
            onFavorite: () {},
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('business-profile-basic-hero')),
        findsOneWidget,
      );
      expect(find.text('Praça Central, Cachoeiras de Macacu'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('business-profile-basic-phone')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('business-profile-actions')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('business-profile-description')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('conteúdo Premium desaparece quando a validade termina', (
    tester,
  ) async {
    final repository = BusinessRepository(
      premiumProjectionLoader: (_) async => PremiumProjectionResult.available(
        premiumUntil: DateTime.now().toUtc().add(const Duration(seconds: 2)),
        data: const {'description': 'Temporário Premium'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PublicBusinessProfile(
          business: basic,
          saved: false,
          onFavorite: () {},
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Temporário Premium'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Temporário Premium'), findsNothing);
    expect(
      find.byKey(const ValueKey('business-profile-basic-hero')),
      findsOneWidget,
    );
  });

  testWidgets('ficha Básica cabe em 320, 360 e 412 dp com texto ampliado', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 360.0, 412.0]) {
      await tester.binding.setSurfaceSize(Size(width, 820));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 820),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: PublicBusinessProfile(
              business: basic,
              saved: false,
              onFavorite: () {},
              repository: BusinessRepository(
                premiumProjectionLoader: (_) async =>
                    const PremiumProjectionResult(
                      status: PremiumProjectionStatus.permissionDenied,
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'largura $width dp');
    }
  });
}
