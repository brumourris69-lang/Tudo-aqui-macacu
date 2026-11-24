import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../tourism/models/tourism_config.dart';
import '../../tourism/widgets/tourism_cover.dart';

/// A Home showcase of the existing Tourism configuration, without its own data.
class HomeTourismCarousel extends StatelessWidget {
  const HomeTourismCarousel({
    super.key,
    required this.config,
    required this.onCategoryTap,
    this.title = 'Explorar Macacu',
    this.description = '',
    this.imageUrl = '',
    this.leading,
  });

  final TourismConfig config;
  final ValueChanged<TourismCategoryConfig> onCategoryTap;
  final String title;
  final String description;
  final String imageUrl;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final categories = config.categories.where((category) => category.active);
    if (categories.isEmpty) return const SizedBox.shrink();
    final sectionTitle = title.trim().isEmpty
        ? 'Explorar Macacu'
        : title.trim();
    final sectionDescription = description.trim().isEmpty
        ? 'Descubra lugares especiais da cidade'
        : description.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
          child: _ExploreGlassHeader(
            title: sectionTitle,
            description: sectionDescription,
            imageUrl: imageUrl,
            leading: leading,
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = ((constraints.maxWidth - 36) * .78).clamp(
              200.0,
              320.0,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final category in categories)
                    Padding(
                      padding: EdgeInsets.only(
                        right: category == categories.last ? 0 : 12,
                      ),
                      child: SizedBox(
                        width: width,
                        child: TourismCover(
                          key: ValueKey(category.key),
                          title: category.name,
                          imageUrl: category.imageUrl,
                          showIcon: false,
                          showAccent: false,
                          fallbackAsset: tourismCategoryFallbackAsset(
                            category.key,
                          ),
                          compact: true,
                          onTap: () => onCategoryTap(category),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ExploreGlassHeader extends StatelessWidget {
  const _ExploreGlassHeader({
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.leading,
  });

  final String title;
  final String description;
  final String imageUrl;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: .82),
                Colors.white.withValues(alpha: .56),
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: Colors.white.withValues(alpha: .92)),
            boxShadow: [
              BoxShadow(
                color: AppColors.ocean.withValues(alpha: .08),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: .95),
                      AppColors.skyTint.withValues(alpha: .86),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .95),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.sky.withValues(alpha: .12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: hasImage
                    ? ClipOval(
                        child: Image.network(
                          imageUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => leading ?? _iconFallback(),
                        ),
                      )
                    : leading ?? _iconFallback(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                        letterSpacing: -.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.explore_rounded,
                color: AppColors.sky.withValues(alpha: .88),
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconFallback() =>
      const Icon(Icons.explore_rounded, color: AppColors.ocean, size: 25);
}
