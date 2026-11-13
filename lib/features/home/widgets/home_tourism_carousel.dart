import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../tourism/models/tourism_config.dart';
import '../../tourism/widgets/tourism_cover.dart';

/// A Home showcase of the existing Tourism configuration, without its own data.
class HomeTourismCarousel extends StatelessWidget {
  const HomeTourismCarousel({
    super.key,
    required this.config,
    required this.onCategoryTap,
    this.title = 'Explore Macacu',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
          child: Row(
            children: [
              if (imageUrl.trim().isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 42,
                      height: 42,
                      color: const Color(0xFFEAF4FF),
                      alignment: Alignment.center,
                      child: leading ?? const Icon(Icons.image_outlined),
                    ),
                  ),
                )
              else
                leading ?? const SizedBox.shrink(),
              if (imageUrl.trim().isNotEmpty || leading != null)
                const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                    if (description.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
