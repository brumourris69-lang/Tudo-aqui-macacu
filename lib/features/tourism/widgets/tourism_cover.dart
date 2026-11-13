import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

String tourismCategoryFallbackAsset(String key) => switch (key) {
  'pontos_turisticos' => 'assets/images/home-tourism-pontos_turisticos.png',
  'trilhas' => 'assets/images/home-tourism-trilhas.png',
  'guias_turisticos' => 'assets/images/home-tourism-roteiros.png',
  'historia_cidade' => 'assets/images/home-tourism-pontos_turisticos.png',
  _ => '',
};

class TourismCover extends StatelessWidget {
  const TourismCover({
    super.key,
    required this.title,
    this.description = '',
    this.imageUrl = '',
    this.icon = Icons.explore_outlined,
    this.onTap,
    this.onEdit,
    this.artwork,
    this.showIcon = true,
    this.showAccent = true,
    this.fallbackAsset = '',
    this.compact = false,
  });

  final String title, description, imageUrl;
  final IconData icon;
  final Widget? artwork;
  final bool showIcon;
  final bool showAccent;
  final bool compact;
  final String fallbackAsset;
  final VoidCallback? onTap, onEdit;

  Widget _fallback() => fallbackAsset.isEmpty
      ? const TourismPlaceholder()
      : Image.asset(
          fallbackAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const TourismPlaceholder(),
        );

  @override
  Widget build(BuildContext context) {
    final radius = compact ? AppRadii.card : AppRadii.feature;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compactHeight = (156 * textScale.clamp(1, 1.4))
        .clamp(156.0, 220.0)
        .toDouble();
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? AppSpacing.md : AppSpacing.lg),
      child: Material(
        color: AppColors.ocean,
        elevation: 1,
        shadowColor: AppColors.ocean.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: SizedBox(
            height: compact ? compactHeight : null,
            child: Stack(
              children: [
                Positioned.fill(
                  child: imageUrl.isEmpty
                      ? _fallback()
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _fallback(),
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : _fallback(),
                        ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.ink.withValues(
                            alpha: compact ? .12 : (showIcon ? .2 : 0),
                          ),
                          AppColors.ink.withValues(
                            alpha: compact ? .82 : (showIcon ? .85 : .65),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (compact)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (showIcon) ...[
                          artwork ?? Icon(icon, color: Colors.white, size: 26),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showAccent)
                                Container(
                                  width: 30,
                                  height: 3,
                                  margin: const EdgeInsets.only(bottom: 7),
                                  decoration: BoxDecoration(
                                    color: AppColors.orange,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showIcon)
                          artwork ?? Icon(icon, color: Colors.white, size: 32)
                        else
                          const SizedBox(height: 48),
                        const SizedBox(height: 48),
                        if (showAccent)
                          Container(
                            width: 38,
                            height: 4,
                            color: AppColors.orange,
                          )
                        else
                          const SizedBox(height: 4),
                        const SizedBox(height: 10),
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            description,
                            style: const TextStyle(
                              color: Colors.white,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (onEdit != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IconButton.filledTonal(
                      onPressed: onEdit,
                      tooltip: 'Editar $title',
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TourismPlaceholder extends StatelessWidget {
  const TourismPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.ocean, AppColors.sky],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ),
    ),
  );
}
