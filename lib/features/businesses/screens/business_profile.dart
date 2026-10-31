import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/share/public_share_content.dart';
import '../../../core/share/public_share_service.dart';
import '../../../core/services/metrics_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/mini_label.dart';
import '../models/business.dart';
import '../services/business_actions.dart';
import '../widgets/business_hero_media.dart';
import '../widgets/business_info_block.dart';

class BusinessProfile extends StatelessWidget {
  const BusinessProfile({
    super.key,
    required this.business,
    required this.saved,
    required this.onFavorite,
    this.canEdit = false,
    this.onEdit,
    this.trackShareMetric = true,
    this.previewMode = false,
  });
  final Business business;
  final bool saved;
  final VoidCallback onFavorite;
  final bool canEdit;
  final VoidCallback? onEdit;
  final bool trackShareMetric;
  final bool previewMode;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 220,
          pinned: true,
          actions: [
            if (!previewMode)
              PublicShareButton(
                content: PublicShareContent(
                  title: business.name,
                  description: business.description,
                ),
                color: Colors.white,
                onShare: () async {
                  if (trackShareMetric) {
                    unawaited(
                      recordMetric(
                        'business_share',
                        target: business.favoriteKey,
                        targetType: 'business',
                      ),
                    );
                  }
                  await sharePublicContentFromContext(
                    context,
                    PublicShareContent(
                      title: business.name,
                      description: business.description,
                    ),
                  );
                },
              ),
            IconButton(
              tooltip: saved
                  ? 'Desfavoritar ${business.name}'
                  : 'Favoritar ${business.name}',
              onPressed: onFavorite,
              icon: Icon(
                saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: saved ? AppColors.orange : Colors.white,
              ),
            ),
            if (canEdit && onEdit != null)
              IconButton(
                tooltip: 'Editar estabelecimento',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
              ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [BusinessHeroMedia(business: business)],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (previewMode) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Prévia · alterações ainda não salvas',
                      style: TextStyle(
                        color: AppColors.ocean,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                Text(
                  business.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  business.subcategory.trim().isEmpty
                      ? business.category
                      : '${business.category} · ${business.subcategory}',
                  style: const TextStyle(
                    color: AppColors.ocean,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        business.location,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (business.statusSpecified)
                      MiniLabel(
                        text: business.open
                            ? 'Status informado: aberto'
                            : 'Status informado: fechado',
                        color: business.open
                            ? const Color(0xFF1E9662)
                            : AppColors.muted,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (business.whatsappUrl.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () => openBusinessAction(
                          context,
                          business,
                          action: 'business_whatsapp',
                          url: business.whatsappUrl,
                          label: 'WhatsApp',
                        ),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('WhatsApp'),
                      ),
                    if (business.phoneUrl.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => openBusinessAction(
                          context,
                          business,
                          action: 'business_phone',
                          url: business.phoneUrl,
                          label: 'Ligação',
                        ),
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('Ligar'),
                      ),
                    if (business.instagramUrl.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => openBusinessAction(
                          context,
                          business,
                          action: 'business_instagram',
                          url: business.instagramUrl,
                          label: 'Instagram',
                        ),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Instagram'),
                      ),
                    if (business.mapsActionUrl.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => openBusinessAction(
                          context,
                          business,
                          action: 'business_map',
                          url: business.mapsActionUrl,
                          label: 'Google Maps',
                        ),
                        icon: const Icon(Icons.directions_outlined),
                        label: const Text('Como chegar'),
                      ),
                  ],
                ),
                if (business.videoUrls.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (
                        var index = 0;
                        index < business.videoUrls.length;
                        index++
                      )
                        OutlinedButton.icon(
                          onPressed: () => openBusinessAction(
                            context,
                            business,
                            action: 'business_video',
                            url: business.videoUrls[index],
                            label: 'Vídeo do estabelecimento',
                          ),
                          icon: const Icon(Icons.play_circle_outline_rounded),
                          label: Text('Assistir vídeo ${index + 1}'),
                        ),
                    ],
                  ),
                ],
                if (business.description.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  InfoBlock(title: 'Sobre', text: business.description),
                ],
                if (business.services.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  InfoBlock(
                    title: 'Serviços',
                    text: business.services.map((item) => '• $item').join('\n'),
                  ),
                ],
                if (business.products.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  InfoBlock(
                    title: 'Produtos',
                    text: business.products.map((item) => '• $item').join('\n'),
                  ),
                ],
                if (business.hours.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  InfoBlock(title: 'Horários', text: business.hours),
                ],
                if (business.additionalInfo.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  InfoBlock(
                    title: 'Informações adicionais',
                    text: business.additionalInfo,
                  ),
                ],
                if (business.promotionTitle.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0D8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.local_offer_outlined,
                              color: AppColors.orange,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Oferta especial',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.ocean,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          business.promotionTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        if (business.promotionDescription.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            business.promotionDescription,
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
