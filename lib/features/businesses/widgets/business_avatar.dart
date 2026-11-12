import 'package:flutter/material.dart';

import '../../../core/media/media_url_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sprite.dart';
import '../models/business.dart';

class BusinessAvatar extends StatelessWidget {
  const BusinessAvatar({
    super.key,
    required this.business,
    this.size = 61,
    this.iconFallback,
  });

  final Business business;
  final double size;
  final Widget? iconFallback;

  @override
  Widget build(BuildContext context) {
    final logo = business.isPremiumEffectiveAt(DateTime.now())
        ? business.logoUrl.trim()
        : '';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: .10),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: logo.isEmpty
          ? _BusinessAvatarFallback(
              business: business,
              size: size,
              iconFallback: iconFallback,
            )
          : Image.network(
              cloudinaryOptimizedImageUrl(logo),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _BusinessAvatarFallback(
                business: business,
                size: size,
                iconFallback: iconFallback,
              ),
            ),
    );
  }
}

class _BusinessAvatarFallback extends StatelessWidget {
  const _BusinessAvatarFallback({
    required this.business,
    required this.size,
    this.iconFallback,
  });

  final Business business;
  final double size;
  final Widget? iconFallback;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.mist,
    child: Center(
      child: iconFallback ?? Sprite(index: business.artwork, size: size * .78),
    ),
  );
}
