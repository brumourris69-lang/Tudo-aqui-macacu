import 'package:flutter/material.dart';
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
  });
  final TourismConfig config;
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
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'Explore por categoria',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      for (final c in config.categories.where((c) => c.active || admin))
        TourismCover(
          title: c.name,
          imageUrl: c.imageUrl,
          description: c.active
              ? c.description
              : 'Categoria inativa — visível somente para admin',
          onTap: () => onCategoryTap(c),
          onEdit: admin && onEditCategory != null
              ? () => onEditCategory!(c)
              : null,
        ),
    ],
  );
}
