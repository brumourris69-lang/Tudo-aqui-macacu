import 'package:flutter/material.dart';

import '../../../core/media/media_url_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sprite.dart';
import '../models/business.dart';

class BusinessAvatar extends StatelessWidget {
  const BusinessAvatar({super.key, required this.business, this.size = 61});

  final Business business;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = business.logoUrl.trim();
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
          ? _BusinessAvatarFallback(business: business, size: size)
          : Image.network(
              cloudinaryOptimizedImageUrl(logo),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  _BusinessAvatarFallback(business: business, size: size),
            ),
    );
  }
}

class _BusinessAvatarFallback extends StatelessWidget {
  const _BusinessAvatarFallback({required this.business, required this.size});

  final Business business;
  final double size;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.mist,
    child: Center(
      child: Sprite(index: business.artwork, size: size * .78),
    ),
  );
}
