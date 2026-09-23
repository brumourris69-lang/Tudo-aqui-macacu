import 'package:flutter/material.dart';

import '../models/business.dart';
import '../repositories/business_repository.dart';

typedef PublishedBusinessListCardBuilder =
    Widget Function(
      BuildContext context,
      Business business,
      bool saved,
      VoidCallback onFavorite,
    );

class PublishedBusinessList extends StatelessWidget {
  const PublishedBusinessList({
    super.key,
    required this.repository,
    required this.fallbackBusinesses,
    required this.saved,
    required this.favorite,
    required this.cardBuilder,
  });

  final BusinessRepository repository;
  final List<Business> fallbackBusinesses;
  final Set<String> saved;
  final ValueChanged<Business> favorite;
  final PublishedBusinessListCardBuilder cardBuilder;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Business>>(
    stream: repository.watchPublishedBusinesses(),
    builder: (context, snapshot) {
      final remote = snapshot.data ?? const <Business>[];
      final items = remote.isEmpty ? fallbackBusinesses : remote;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
        child: Column(
          children: items
              .map(
                (business) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: cardBuilder(
                    context,
                    business,
                    _isBusinessSaved(saved, business),
                    () => favorite(business),
                  ),
                ),
              )
              .toList(),
        ),
      );
    },
  );
}

bool _isBusinessSaved(Set<String> saved, Business business) =>
    saved.contains(business.favoriteKey) || saved.contains(business.name);
