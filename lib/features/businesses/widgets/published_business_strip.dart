import 'package:flutter/material.dart';

import '../models/business.dart';
import '../repositories/business_repository.dart';

typedef PublishedBusinessStripCardBuilder =
    Widget Function(
      BuildContext context,
      Business business,
      bool saved,
      VoidCallback onFavorite,
    );

class PublishedBusinessStrip extends StatelessWidget {
  const PublishedBusinessStrip({
    super.key,
    required this.repository,
    required this.fallbackBusinesses,
    required this.saved,
    required this.favorite,
    required this.cardBuilder,
    this.limit = 6,
  });

  final BusinessRepository repository;
  final List<Business> fallbackBusinesses;
  final Set<String> saved;
  final ValueChanged<Business> favorite;
  final PublishedBusinessStripCardBuilder cardBuilder;
  final int limit;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Business>>(
    stream: repository.watchPublishedBusinesses(),
    builder: (context, snapshot) {
      final remote = snapshot.data == null
          ? const <Business>[]
          : BusinessRepository.featuredBusinesses(snapshot.data!);
      final items = (remote.isEmpty ? fallbackBusinesses : remote)
          .take(limit)
          .toList();
      return SizedBox(
        height: 230,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, index) => SizedBox(
            width: 292,
            child: cardBuilder(
              context,
              items[index],
              _isBusinessSaved(saved, items[index]),
              () => favorite(items[index]),
            ),
          ),
        ),
      );
    },
  );
}

bool _isBusinessSaved(Set<String> saved, Business business) =>
    saved.contains(business.favoriteKey) || saved.contains(business.name);
