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
  });

  final String title, description, imageUrl;
  final IconData icon;
  final Widget? artwork;
  final VoidCallback? onTap, onEdit;

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
                  ? const TourismPlaceholder()
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const TourismPlaceholder(),
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : const TourismPlaceholder(),
                    ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.ink.withValues(alpha: .2),
                      AppColors.ink.withValues(alpha: .85),
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
                  artwork ?? Icon(icon, color: Colors.white, size: 32),
                  const SizedBox(height: 48),
                  Container(width: 38, height: 4, color: AppColors.orange),
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
