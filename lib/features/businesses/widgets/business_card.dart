import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/mini_label.dart';
import '../models/business.dart';
import 'business_avatar.dart';

class BusinessCard extends StatelessWidget {
  const BusinessCard({
    super.key,
    required this.business,
    required this.saved,
    required this.onFavorite,
    required this.onOpen,
    required this.onViewBusiness,
    required this.onWhatsApp,
    this.compact = false,
  });

  final Business business;
  final bool saved;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;
  final VoidCallback onViewBusiness;
  final VoidCallback onWhatsApp;
  final bool compact;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BusinessAvatar(business: business, size: 61),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (business.featured)
                            const MiniLabel(
                              text: 'DESTAQUE',
                              color: AppColors.orange,
                            ),
                          const Spacer(),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: onFavorite,
                            icon: Icon(
                              saved
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: saved ? AppColors.orange : AppColors.sky,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        business.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        business.subcategory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              business.description,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 15,
                  color: AppColors.ocean,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    business.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (business.open)
                  const MiniLabel(text: 'ABERTO', color: Color(0xFF1E9662)),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onWhatsApp,
                      icon: const Icon(Icons.chat_outlined, size: 17),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: FilledButton(
                      onPressed: onViewBusiness,
                      child: const Text('Ver negócio'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
