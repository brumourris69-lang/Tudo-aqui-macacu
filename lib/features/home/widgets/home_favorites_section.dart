import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../businesses/models/business.dart';
import '../../tourism/models/tourist_spot.dart';
import '../../tourism/models/tourism_category.dart';

typedef HomeBusinessResolver = Future<Business?> Function(String id);
typedef HomeTourismResolver = Future<TouristSpot?> Function(String id);

/// A small, personalized Home rail. Each item is resolved through the public
/// detail endpoint so stale favorites never expose drafts or tombstones.
class HomeFavoritesSection extends StatefulWidget {
  const HomeFavoritesSection({
    super.key,
    required this.businessIds,
    required this.tourismIds,
    required this.resolveBusiness,
    required this.resolveTourism,
    required this.onOpenBusiness,
    required this.onOpenTourism,
    required this.onRemoveBusiness,
    required this.onRemoveTourism,
    required this.onViewAll,
  });

  final List<String> businessIds;
  final List<String> tourismIds;
  final HomeBusinessResolver resolveBusiness;
  final HomeTourismResolver resolveTourism;
  final ValueChanged<Business> onOpenBusiness;
  final ValueChanged<TouristSpot> onOpenTourism;
  final ValueChanged<Business> onRemoveBusiness;
  final ValueChanged<TouristSpot> onRemoveTourism;
  final VoidCallback onViewAll;

  @override
  State<HomeFavoritesSection> createState() => _HomeFavoritesSectionState();
}

class _HomeFavoritesSectionState extends State<HomeFavoritesSection> {
  late Future<List<_HomeFavoriteItem>> _items;

  @override
  void initState() {
    super.initState();
    _items = _loadItems();
  }

  @override
  void didUpdateWidget(covariant HomeFavoritesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.businessIds, widget.businessIds) ||
        !listEquals(oldWidget.tourismIds, widget.tourismIds) ||
        oldWidget.resolveBusiness != widget.resolveBusiness ||
        oldWidget.resolveTourism != widget.resolveTourism) {
      _items = _loadItems();
    }
  }

  List<_HomeFavoriteReference> _previewReferences() {
    final result = <_HomeFavoriteReference>[];
    final seenBusinesses = <String>{};
    final seenTourism = <String>{};
    final count = widget.businessIds.length > widget.tourismIds.length
        ? widget.businessIds.length
        : widget.tourismIds.length;
    for (var index = 0; index < count && result.length < 6; index++) {
      if (index < widget.businessIds.length) {
        final id = widget.businessIds[index];
        if (id.isNotEmpty && seenBusinesses.add(id)) {
          result.add(_HomeFavoriteReference.business(id));
        }
      }
      if (result.length < 6 && index < widget.tourismIds.length) {
        final id = widget.tourismIds[index];
        if (id.isNotEmpty && seenTourism.add(id)) {
          result.add(_HomeFavoriteReference.tourism(id));
        }
      }
    }
    return result;
  }

  Future<List<_HomeFavoriteItem>> _loadItems() async {
    final references = _previewReferences();
    final resolved = await Future.wait(
      references.map((reference) async {
        if (reference.businessId case final id?) {
          final business = await widget.resolveBusiness(id);
          return business == null ? null : _HomeFavoriteItem.business(business);
        }
        final id = reference.tourismId!;
        final spot = await widget.resolveTourism(id);
        return spot == null ? null : _HomeFavoriteItem.tourism(spot);
      }),
    );
    return resolved.whereType<_HomeFavoriteItem>().toList(growable: false);
  }

  void _retry() => setState(() => _items = _loadItems());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<_HomeFavoriteItem>>(
    future: _items,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _HomeFavoritesError(onRetry: _retry);
      }
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: SizedBox(
            height: 54,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Carregando seus favoritos',
              ),
            ),
          ),
        );
      }
      final items = snapshot.data!;
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Seus Favoritos',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onViewAll,
                  child: const Text('Ver todos'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 198,
            child: ListView.separated(
              key: const ValueKey('home-favorites-rail'),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return switch (item) {
                  _BusinessFavorite(:final business) => _FavoritePreviewCard(
                    key: ValueKey('home-favorite-card-business-${business.id}'),
                    title: business.name,
                    category: business.categoryLabel,
                    imageUrl: business.imageUrl,
                    fallbackIcon: Icons.storefront_outlined,
                    onOpen: () => widget.onOpenBusiness(business),
                    onRemove: () => widget.onRemoveBusiness(business),
                    removeKey: ValueKey(
                      'home-favorite-remove-business-${business.id}',
                    ),
                  ),
                  _TourismFavorite(:final spot) => _FavoritePreviewCard(
                    key: ValueKey('home-favorite-card-tourism-${spot.id}'),
                    title: spot.title,
                    category: _tourismCategoryLabel(spot.category),
                    imageUrl: spot.images.isEmpty ? '' : spot.images.first,
                    fallbackIcon: Icons.landscape_outlined,
                    onOpen: () => widget.onOpenTourism(spot),
                    onRemove: () => widget.onRemoveTourism(spot),
                    removeKey: ValueKey(
                      'home-favorite-remove-tourism-${spot.id}',
                    ),
                  ),
                };
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
    },
  );
}

String _tourismCategoryLabel(String key) {
  for (final category in TourismCategory.values) {
    if (TourismCategory.normalize(key) == category.key) return category.name;
  }
  return 'Ponto turístico';
}

class _HomeFavoriteReference {
  const _HomeFavoriteReference.business(String id)
    : businessId = id,
      tourismId = null;
  const _HomeFavoriteReference.tourism(String id)
    : businessId = null,
      tourismId = id;

  final String? businessId;
  final String? tourismId;
}

sealed class _HomeFavoriteItem {
  const _HomeFavoriteItem();
  const factory _HomeFavoriteItem.business(Business business) =
      _BusinessFavorite;
  const factory _HomeFavoriteItem.tourism(TouristSpot spot) = _TourismFavorite;
}

final class _BusinessFavorite extends _HomeFavoriteItem {
  const _BusinessFavorite(this.business);
  final Business business;
}

final class _TourismFavorite extends _HomeFavoriteItem {
  const _TourismFavorite(this.spot);
  final TouristSpot spot;
}

class _FavoritePreviewCard extends StatelessWidget {
  const _FavoritePreviewCard({
    super.key,
    required this.title,
    required this.category,
    required this.imageUrl,
    required this.fallbackIcon,
    required this.onOpen,
    required this.onRemove,
    required this.removeKey,
  });

  final String title;
  final String category;
  final String imageUrl;
  final IconData fallbackIcon;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final Key removeKey;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 238,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 78,
                  height: 108,
                  child: imageUrl.isEmpty
                      ? _FavoriteImagePlaceholder(icon: fallbackIcon)
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              _FavoriteImagePlaceholder(icon: fallbackIcon),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        key: removeKey,
                        tooltip: 'Remover dos favoritos',
                        onPressed: onRemove,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        icon: const Icon(
                          Icons.favorite_rounded,
                          color: AppColors.orange,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FavoriteImagePlaceholder extends StatelessWidget {
  const _FavoriteImagePlaceholder({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.mist,
    child: Center(child: Icon(icon, size: 30, color: AppColors.ocean)),
  );
}

class _HomeFavoritesError extends StatelessWidget {
  const _HomeFavoritesError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
    child: Card(
      color: AppColors.soft,
      child: ListTile(
        leading: const Icon(Icons.cloud_off_outlined, color: AppColors.muted),
        title: const Text('Não foi possível carregar seus favoritos.'),
        trailing: IconButton(
          tooltip: 'Tentar carregar favoritos novamente',
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ),
    ),
  );
}
