import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

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
  });

  final String title, description, imageUrl;
  final IconData icon;
  final Widget? artwork;
  final bool showIcon;
  final bool showAccent;
  final String fallbackAsset;
  final VoidCallback? onTap, onEdit;

  Widget _fallback() => fallbackAsset.isEmpty
      ? const TourismPlaceholder()
      : Image.asset(
          fallbackAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.ocean),
        );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: AppColors.ocean,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                      AppColors.ink.withValues(alpha: showIcon ? .2 : 0),
                      AppColors.ink.withValues(alpha: showIcon ? .85 : .65),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showIcon)
                    artwork ?? Icon(icon, color: Colors.white, size: 32)
                  else
                    const SizedBox(height: 48),
                  const SizedBox(height: 48),
                  if (showAccent)
                    Container(width: 38, height: 4, color: AppColors.orange)
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
                      style: const TextStyle(color: Colors.white, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            if (onEdit != null)
              Positioned(
                top: 8,
                right: 8,
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
  );
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
    child: Center(
      child: Icon(Icons.explore_outlined, color: Colors.white24, size: 72),
    ),
  );
}
