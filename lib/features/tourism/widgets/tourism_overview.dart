import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../models/tourism_config.dart';
import 'tourism_cover.dart';

class TourismOverview extends StatelessWidget {
  const TourismOverview({
    super.key,
    required this.config,
    required this.admin,
    required this.onCategoryTap,
    this.onEditHero,
    this.onEditCategory,
    this.iconBuilder,
  });
  final TourismConfig config;
  final Widget Function(String key)? iconBuilder;
  final bool admin;
  final ValueChanged<TourismCategoryConfig> onCategoryTap;
  final VoidCallback? onEditHero;
  final ValueChanged<TourismCategoryConfig>? onEditCategory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TourismCover(
        title: config.title,
        description: config.subtitle,
        imageUrl: config.imageUrl,
        onEdit: admin ? onEditHero : null,
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Explore por categoria',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
      for (final c in config.categories.where((c) => c.active || admin))
        TourismCover(
          key: ValueKey('tourism-category-${c.key}'),
          title: c.name,
          artwork: iconBuilder?.call(c.key),
          imageUrl: c.imageUrl,
          fallbackAsset: tourismCategoryFallbackAsset(c.key),
          description: c.active
              ? c.description
              : 'Categoria inativa — visível somente para admin',
          onTap: () => onCategoryTap(c),
          onEdit: admin && onEditCategory != null
              ? () => onEditCategory!(c)
              : null,
          compact: true,
        ),
    ],
  );
}
