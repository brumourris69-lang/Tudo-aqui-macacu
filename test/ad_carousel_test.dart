import 'dart:async';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/screens/business_profile.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

// Offline snapshots exercise the actual carousel without changing Firebase.
// ignore: subtype_of_sealed_class
class _AdDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _AdDoc(this.fields);
  final Map<String, dynamic> fields;
  @override
  String get id => (fields['title'] ?? 'ad').toString();
  @override
  DocumentReference<Map<String, dynamic>> get reference => _AdReference();
  @override
  Map<String, dynamic> data() => fields;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _AdReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Ads implements QuerySnapshot<Map<String, dynamic>> {
  _Ads(List<Map<String, dynamic>> data) : docs = data.map(_AdDoc.new).toList();
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Stream<PublicContentSnapshot> _businesses() => Stream.value(
  PublicContentSnapshot([
    PublicContentDocument('business-1', const {
      'name': 'Comércio público',
      'published': true,
      'active': true,
    }, _AdReference()),
  ]),
);

void main() {
  testWidgets(
    'real slides swipe, autoplay, order, indicators and shrinking list',
    (tester) async {
      final stream = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      addTearDown(stream.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCarousel(
              adsStream: stream.stream,
              businessesSnapshotStreamFactory: _businesses,
            ),
          ),
        ),
      );
      stream.add(
        _Ads([
          {'title': 'Terceiro', 'businessId': 'business-1', 'order': 30},
          {'title': 'Primeiro', 'businessId': 'business-1', 'order': 10},
          {'title': 'Segundo', 'businessId': 'business-1', 'order': 20},
          {
            'title': 'Inativo',
            'businessId': 'business-1',
            'order': 0,
            'active': false,
          },
          {
            'title': 'Expirado',
            'businessId': 'business-1',
            'expiresAt': Timestamp.fromDate(DateTime(2000)),
          },
        ]),
      );
      await tester.pumpAndSettle();
      final view = tester.widget<PageView>(find.byType(PageView));
      expect(
        (view.childrenDelegate as SliverChildBuilderDelegate).childCount,
        3,
      );
      expect(view.controller!.page, 0);
      final labels = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.label);
      expect(labels, contains('Primeiro'));
      expect(labels, contains('Anúncio 1 de 3'));
      expect(find.text('ESPAÇO PUBLICITÁRIO'), findsNothing);
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(view.controller!.page, closeTo(1, .01));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(view.controller!.page, closeTo(2, .01));
      stream.add(_Ads([]));
      await tester.pumpAndSettle();
      expect(view.controller!.page, 0);
      final fallback = tester.widget<PageView>(find.byType(PageView));
      expect(
        (fallback.childrenDelegate as SliverChildBuilderDelegate).childCount,
        1,
      );
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any((s) => s.properties.label == 'Anúncio 1 de 1'),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('carousel caps active ads at ten in configured order', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdCarousel(
            businessesSnapshotStreamFactory: _businesses,
            adsStream: Stream.value(
              _Ads([
                for (var index = 12; index >= 1; index--)
                  {
                    'title': 'Anúncio $index',
                    'businessId': 'business-1',
                    'order': index,
                  },
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final carousel = tester.widget<PageView>(find.byType(PageView));
    expect(
      (carousel.childrenDelegate as SliverChildBuilderDelegate).childCount,
      10,
    );
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((semantics) => semantics.properties.label),
      contains('Anúncio 1 de 10'),
    );
    expect(find.text('Anúncio 11'), findsNothing);
    expect(find.text('Anúncio 12'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('8:3 card fits mobile widths without overflow', (tester) async {
    for (final width in [320.0, 360.0, 480.0]) {
      await tester.binding.setSurfaceSize(Size(width, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCarousel(
              key: ValueKey(width),
              adsStream: Stream.value(_Ads([])),
              businessesSnapshotStreamFactory: _businesses,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = tester.getSize(
        find
            .descendant(
              of: find.byType(PageView),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(
        card.width / card.height,
        closeTo(AdCarousel.bannerAspectRatio, .001),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('banner opens the linked business profile in-app', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdCarousel(
            adsStream: Stream.value(
              _Ads([
                {
                  'title': 'Banner do comércio',
                  'businessId': 'business-1',
                  'link': 'https://legacy.example.invalid',
                },
              ]),
            ),
            businessesSnapshotStreamFactory: _businesses,
            businessResolver: (id) async => Business.fromData(id, {
              'name': 'Comércio público',
              'published': true,
              'active': true,
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ad-business-business-1')));
    await tester.pumpAndSettle();
    expect(find.byType(BusinessProfile), findsOneWidget);
    expect(find.text('Comércio público'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('legacy links and unavailable business targets stay hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdCarousel(
            adsStream: Stream.value(
              _Ads([
                {'title': 'Banner antigo', 'link': 'https://example.com'},
                {'title': 'Destino removido', 'businessId': 'deleted-id'},
              ]),
            ),
            businessesSnapshotStreamFactory: _businesses,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Banner antigo'), findsNothing);
    expect(find.text('Destino removido'), findsNothing);
    expect(find.bySemanticsLabel('Anuncie aqui'), findsOneWidget);
    final carousel = tester.widget<PageView>(find.byType(PageView));
    expect(
      (carousel.childrenDelegate as SliverChildBuilderDelegate).childCount,
      1,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('supplied artwork framing crop preserves the banner composition', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await rootBundle.load(
        'assets/images/home-ad-anuncie-aqui.png',
      );
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final source = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      final fit = applyBoxFit(BoxFit.cover, source, const Size(1600, 600));
      final crop = Alignment.center.inscribe(fit.source, Offset.zero & source);
      // The supplied banner occupies y=120..775; only its outer light frame is removed.
      expect(crop.top, lessThanOrEqualTo(120));
      expect(crop.bottom, greaterThanOrEqualTo(775));
      expect(crop.left, 0);
      expect(crop.right, source.width);
      frame.image.dispose();
      codec.dispose();
    });
  });
}
