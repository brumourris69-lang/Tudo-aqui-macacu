import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
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
    this.onShare,
    this.compact = false,
  });

  final Business business;
  final bool saved;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;
  final VoidCallback onViewBusiness;
  final VoidCallback onWhatsApp;
  final Future<void> Function()? onShare;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hasWhatsApp = business.whatsappUrl.isNotEmpty;
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: AppColors.ocean.withValues(alpha: .12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.cardLarge),
        side: BorderSide(color: AppColors.sky.withValues(alpha: .08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.cardLarge),
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (business.displayImageUrls.isNotEmpty)
              _BusinessCardCover(
                businessName: business.name,
                imageUrl: business.displayImageUrls.first,
              ),
            Padding(
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
                                if (onShare != null)
                                  IconButton(
                                    tooltip: 'Compartilhar ${business.name}',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: onShare,
                                    icon: const Icon(
                                      Icons.share_outlined,
                                      color: AppColors.sky,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: saved
                                      ? 'Remover dos favoritos ${business.name}'
                                      : 'Favoritar ${business.name}',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: onFavorite,
                                  icon: Icon(
                                    saved
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: saved
                                        ? AppColors.orange
                                        : AppColors.sky,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              business.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              business.categoryLabel,
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
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                        ],
                      ),
                      if (business.statusSpecified) ...[
                        const SizedBox(height: 5),
                        MiniLabel(
                          text: business.open
                              ? 'Status informado: aberto'
                              : 'Status informado: fechado',
                          color: business.open
                              ? const Color(0xFF1E9662)
                              : AppColors.muted,
                        ),
                      ],
                    ],
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stackActions =
                            constraints.maxWidth < 380 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.2;
                        final whatsapp = hasWhatsApp
                            ? OutlinedButton.icon(
                                onPressed: onWhatsApp,
                                icon: const Icon(Icons.chat_outlined, size: 17),
                                label: const Text('WhatsApp'),
                              )
                            : null;
                        final viewBusiness = FilledButton(
                          onPressed: onViewBusiness,
                          child: const Text('Ver negócio'),
                        );
                        if (stackActions) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (whatsapp != null) ...[
                                whatsapp,
                                const SizedBox(height: 9),
                              ],
                              viewBusiness,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            if (whatsapp != null) ...[
                              Expanded(child: whatsapp),
                              const SizedBox(width: 9),
                            ],
                            Expanded(child: viewBusiness),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessCardCover extends StatelessWidget {
  const _BusinessCardCover({
    required this.businessName,
    required this.imageUrl,
  });

  final String businessName;
  final String imageUrl;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 2.9,
    child: Semantics(
      label: 'Capa de $businessName',
      child: Image.network(
        imageUrl,
        key: ValueKey('business-card-cover-$businessName'),
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const ColoredBox(
                color: AppColors.mist,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
        errorBuilder: (_, _, _) => const ColoredBox(
          color: AppColors.mist,
          child: Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    ),
  );
}
