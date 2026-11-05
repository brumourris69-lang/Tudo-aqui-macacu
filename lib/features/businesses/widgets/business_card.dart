import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mini_label.dart';
import '../models/business.dart';
import 'business_avatar.dart';
import 'business_hours.dart';

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
    this.iconFallback,
    this.compact = false,
    this.featuredShowcase = false,
    this.openingStatusClock,
  });

  final Business business;
  final bool saved;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;
  final VoidCallback onViewBusiness;
  final VoidCallback onWhatsApp;
  final Future<void> Function()? onShare;
  final Widget? iconFallback;
  final bool compact;
  final bool featuredShowcase;
  final DateTime Function()? openingStatusClock;

  @override
  Widget build(BuildContext context) {
    if (featuredShowcase) {
      return _FeaturedBusinessShowcase(
        business: business,
        saved: saved,
        onFavorite: onFavorite,
        onOpen: onOpen,
        onShare: onShare,
        iconFallback: iconFallback,
        openingStatusClock: openingStatusClock,
      );
    }
    final hasWhatsApp = business.whatsappUrl.isNotEmpty;
    final cover = business.displayImageUrls.isEmpty
        ? ''
        : business.displayImageUrls.first;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact || cover.isNotEmpty)
              _BusinessCardCover(businessName: business.name, imageUrl: cover),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BusinessAvatar(
                        business: business,
                        size: 61,
                        iconFallback: iconFallback,
                      ),
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
                      if (business.statusSpecified ||
                          business.hours.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        BusinessOpeningStatusBadge(
                          hours: business.hours,
                          fallbackSpecified: business.statusSpecified,
                          fallbackOpen: business.open,
                          clock: openingStatusClock,
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
    this.aspectRatio = 2.9,
  });

  final String businessName;
  final String imageUrl;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: aspectRatio,
    child: Semantics(
      label: imageUrl.isEmpty
          ? 'Imagem indisponível para $businessName'
          : 'Capa de $businessName',
      child: imageUrl.isEmpty
          ? const _BusinessCoverPlaceholder()
          : Image.network(
              imageUrl,
              key: ValueKey('business-card-cover-$businessName'),
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : const _BusinessCoverPlaceholder(),
              errorBuilder: (_, _, _) => const _BusinessCoverPlaceholder(),
            ),
    ),
  );
}

class _BusinessCoverPlaceholder extends StatelessWidget {
  const _BusinessCoverPlaceholder();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.skyTint, AppColors.mist],
      ),
    ),
    child: Center(
      child: Icon(
        Icons.storefront_outlined,
        color: AppColors.ocean.withValues(alpha: .42),
        size: 42,
      ),
    ),
  );
}

class _FeaturedBusinessShowcase extends StatelessWidget {
  const _FeaturedBusinessShowcase({
    required this.business,
    required this.saved,
    required this.onFavorite,
    required this.onOpen,
    required this.onShare,
    required this.iconFallback,
    required this.openingStatusClock,
  });

  final Business business;
  final bool saved;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;
  final Future<void> Function()? onShare;
  final Widget? iconFallback;
  final DateTime Function()? openingStatusClock;

  @override
  Widget build(BuildContext context) {
    final cover = business.displayImageUrls.isEmpty
        ? ''
        : business.displayImageUrls.first;
    final category = business.categoryLabel.trim();

    return Align(
      alignment: Alignment.topCenter,
      child: Card(
        key: const ValueKey('featured-business-showcase-card'),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shadowColor: AppColors.ocean.withValues(alpha: .12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: AppColors.ocean.withValues(alpha: .08)),
        ),
        child: InkWell(
          onTap: onOpen,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final coverHeight = (constraints.maxWidth * .57)
                  .clamp(148.0, 168.0)
                  .toDouble();
              const avatarSize = 68.0;
              return Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        key: const ValueKey('featured-business-cover'),
                        height: coverHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _BusinessCardCover(
                              businessName: business.name,
                              imageUrl: cover,
                              aspectRatio: 1.8,
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x00082B4C),
                                    Color(0x00082B4C),
                                    Color(0x99082B4C),
                                  ],
                                  stops: [0, .58, 1],
                                ),
                              ),
                            ),
                            if (business.featured)
                              const Positioned(
                                top: 12,
                                left: 12,
                                child: MiniLabel(
                                  text: 'DESTAQUE',
                                  color: AppColors.orange,
                                ),
                              ),
                            Positioned(
                              top: 5,
                              right: 5,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (onShare != null)
                                    _ShowcaseActionButton(
                                      tooltip: 'Compartilhar ${business.name}',
                                      onPressed: onShare,
                                      icon: Icons.share_outlined,
                                    ),
                                  _ShowcaseActionButton(
                                    tooltip: saved
                                        ? 'Remover dos favoritos ${business.name}'
                                        : 'Favoritar ${business.name}',
                                    onPressed: onFavorite,
                                    icon: saved
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    foreground: saved
                                        ? AppColors.orange
                                        : AppColors.ocean,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          14,
                          avatarSize / 2 + 5,
                          14,
                          13,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              business.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w700,
                                    height: 1.18,
                                  ),
                            ),
                            if (category.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                category,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: AppColors.muted),
                              ),
                            ],
                            const SizedBox(height: 7),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.location_on_rounded,
                                    size: 16,
                                    color: AppColors.sky,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    business.location,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: AppColors.muted),
                                  ),
                                ),
                              ],
                            ),
                            if (business.hours.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              BusinessOpeningStatusBadge(
                                hours: business.hours,
                                fallbackSpecified: false,
                                fallbackOpen: false,
                                clock: openingStatusClock,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: coverHeight - avatarSize / 2,
                    left: 13,
                    child: Container(
                      width: avatarSize,
                      height: avatarSize,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: .18),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: BusinessAvatar(
                        business: business,
                        size: avatarSize - 8,
                        iconFallback: iconFallback,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ShowcaseActionButton extends StatelessWidget {
  const _ShowcaseActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.foreground = AppColors.ocean,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .94),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(icon, color: foreground, size: 18),
    ),
  );
}
