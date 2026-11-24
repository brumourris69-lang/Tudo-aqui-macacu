import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Placeholder that keeps the public business layout stable while data loads.
class BusinessCardSkeleton extends StatelessWidget {
  const BusinessCardSkeleton({
    super.key,
    this.featured = false,
    this.showCover = false,
  });

  final bool featured;
  final bool showCover;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Carregando estabelecimento',
    child: ExcludeSemantics(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: featured ? _featuredCard() : _standardCard(),
      ),
    ),
  );

  Widget _standardCard() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showCover) const _SkeletonBlock(height: 112, radius: 0),
      Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _SkeletonBlock(width: 58, height: 58, circle: true),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBlock(width: 158, height: 15),
                      SizedBox(height: 9),
                      _SkeletonBlock(width: 96, height: 11),
                    ],
                  ),
                ),
                const _SkeletonBlock(width: 34, height: 34, circle: true),
              ],
            ),
            const SizedBox(height: 14),
            const _SkeletonBlock(height: 10),
            const SizedBox(height: 7),
            const _SkeletonBlock(width: 210, height: 10),
            const SizedBox(height: 14),
            const _SkeletonBlock(height: 44, radius: AppRadii.control),
          ],
        ),
      ),
    ],
  );

  Widget _featuredCard() => SizedBox(
    height: 320,
    child: Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SkeletonBlock(height: 164, radius: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 39, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _SkeletonBlock(width: 175, height: 14),
                  SizedBox(height: 9),
                  _SkeletonBlock(width: 105, height: 11),
                  SizedBox(height: 16),
                  _SkeletonBlock(height: 10),
                  SizedBox(height: 13),
                  _SkeletonBlock(width: 122, height: 22, radius: 11),
                ],
              ),
            ),
          ],
        ),
        const Positioned(
          top: 5,
          right: 8,
          child: Row(
            children: [
              _SkeletonBlock(width: 38, height: 38, circle: true),
              SizedBox(width: 7),
              _SkeletonBlock(width: 38, height: 38, circle: true),
            ],
          ),
        ),
        Positioned(
          top: 130,
          left: 13,
          child: Container(
            width: 68,
            height: 68,
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const _SkeletonBlock(circle: true),
          ),
        ),
      ],
    ),
  );
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    this.width,
    this.height = 12,
    this.radius = 7,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.mist, AppColors.skyTint, AppColors.mist],
        stops: [0, .48, 1],
      ),
      borderRadius: circle ? null : BorderRadius.circular(radius),
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
    ),
  );
}
