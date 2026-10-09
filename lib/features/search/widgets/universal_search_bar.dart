import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class UniversalSearchBar extends StatelessWidget {
  const UniversalSearchBar({
    super.key,
    required this.onTap,
    this.placeholder = 'O que você procura em Macacu?',
  });

  final VoidCallback onTap;
  final String placeholder;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 2,
    shadowColor: AppColors.ink.withValues(alpha: .10),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: AppColors.sky, size: 23),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.sky,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}
