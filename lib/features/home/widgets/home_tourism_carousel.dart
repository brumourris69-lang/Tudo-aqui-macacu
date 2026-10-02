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
    this.iconBuilder,
  });

  final TourismConfig config;
  final ValueChanged<TourismCategoryConfig> onCategoryTap;
  final Widget Function(String key)? iconBuilder;

  @override
  Widget build(BuildContext context) {
    final categories = config.categories.where((category) => category.active);
    if (categories.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
          child: Text(
            'Explore Macacu',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
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
                          artwork: iconBuilder?.call(category.key),
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
