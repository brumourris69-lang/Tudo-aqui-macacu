import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/share/public_share_content.dart';
import '../../../core/share/public_share_service.dart';
import '../../../core/services/metrics_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_brand.dart';
import '../../../core/widgets/mini_label.dart';
import '../models/business.dart';
import '../models/establishment_listing_level.dart';
import '../repositories/business_repository.dart';
import '../services/business_actions.dart';
import '../widgets/business_action_button.dart';
import '../widgets/business_avatar.dart';
import '../widgets/business_hero_media.dart';
import '../widgets/business_hours.dart';
import '../widgets/business_info_block.dart';

const _phoneGradient = [Color(0xFF39D978), Color(0xFF087C3A)];
const _whatsappGradient = [Color(0xFF32D66E), Color(0xFF087E48)];
const _instagramGradient = [
  Color(0xFF8134AF),
  Color(0xFFE1306C),
  Color(0xFFFF9A26),
];
const _mapsGradient = [Color(0xFF1488F5), Color(0xFF064BB8)];
const _youtubeGradient = [Color(0xFFFF3D36), Color(0xFFC5161D)];
const _vimeoGradient = [Color(0xFF36A9E8), Color(0xFF075B9D)];

class _BusinessAction {
  const _BusinessAction({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.action,
    required this.url,
    required this.label,
  });

  final Key key;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final String action;
  final String url;
  final String label;
}

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
    this.previewTier,
    this.openingStatusClock,
  });

  final Business business;
  final bool saved;
  final VoidCallback onFavorite;
  final bool canEdit;
  final VoidCallback? onEdit;
  final bool trackShareMetric;
  final bool previewMode;
  final ListingTier? previewTier;
  final DateTime Function()? openingStatusClock;

  Business get displayBusiness =>
      previewMode ? business : business.visiblePublicDataAt(DateTime.now());
  bool get showPremiumContent => previewMode
      ? previewTier == null || previewTier == ListingTier.premium
      : displayBusiness.isPremiumEffectiveAt(DateTime.now());

  List<_BusinessAction> _actions() {
    if (!showPremiumContent) return [];
    final actions = <_BusinessAction>[];
    if (displayBusiness.phoneUrl.isNotEmpty) {
      actions.add(
        _BusinessAction(
          key: const ValueKey('business-action-phone'),
          icon: Icons.call_rounded,
          title: 'Ligar',
          subtitle: 'Ligar agora',
          colors: _phoneGradient,
          action: 'business_phone',
          url: displayBusiness.phoneUrl,
          label: 'Ligação',
        ),
      );
    }
    if (displayBusiness.whatsappUrl.isNotEmpty) {
      actions.add(
        _BusinessAction(
          key: const ValueKey('business-action-whatsapp'),
          icon: Icons.chat_rounded,
          title: 'WhatsApp',
          subtitle: 'Conversar agora',
          colors: _whatsappGradient,
          action: 'business_whatsapp',
          url: displayBusiness.whatsappUrl,
          label: 'WhatsApp',
        ),
      );
    }
    if (displayBusiness.instagramUrl.isNotEmpty) {
      actions.add(
        _BusinessAction(
          key: const ValueKey('business-action-instagram'),
          icon: Icons.camera_alt_rounded,
          title: 'Instagram',
          subtitle: 'Ver perfil',
          colors: _instagramGradient,
          action: 'business_instagram',
          url: displayBusiness.instagramUrl,
          label: 'Instagram',
        ),
      );
    }
    if (displayBusiness.mapsActionUrl.isNotEmpty) {
      actions.add(
        _BusinessAction(
          key: const ValueKey('business-action-maps'),
          icon: Icons.location_on_rounded,
          title: 'Como chegar',
          subtitle: 'Ver no mapa',
          colors: _mapsGradient,
          action: 'business_map',
          url: displayBusiness.mapsActionUrl,
          label: 'Google Maps',
        ),
      );
    }
    for (var index = 0; index < displayBusiness.videoUrls.length; index++) {
      final url = displayBusiness.videoUrls[index];
      final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
      final isVimeo = host == 'vimeo.com' || host.endsWith('.vimeo.com');
      actions.add(
        _BusinessAction(
          key: ValueKey('business-action-video-$index'),
          icon: Icons.play_circle_fill_rounded,
          title: 'Assistir vídeo',
          subtitle: 'Vídeo ${index + 1}',
          colors: isVimeo ? _vimeoGradient : _youtubeGradient,
          action: 'business_video',
          url: url,
          label: 'Vídeo do estabelecimento',
        ),
      );
    }
    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions();
    return Scaffold(
      backgroundColor: AppColors.soft,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 68,
            backgroundColor: AppColors.ocean,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(AppRadii.card),
              ),
            ),
            title: const AppBrand(inverse: true, compact: true),
            actions: [
              if (!previewMode)
                PublicShareButton(
                  key: const ValueKey('business-profile-share'),
                  content: PublicShareContent(
                    title: displayBusiness.name,
                    description: displayBusiness.description,
                  ),
                  color: Colors.white,
                  onShare: () async {
                    if (trackShareMetric) {
                      unawaited(
                        recordMetric(
                          'business_share',
                          target: displayBusiness.favoriteKey,
                          targetType: 'business',
                        ),
                      );
                    }
                    await sharePublicContentFromContext(
                      context,
                      PublicShareContent(
                        title: displayBusiness.name,
                        description: displayBusiness.description,
                      ),
                    );
                  },
                ),
              IconButton(
                tooltip: saved
                    ? 'Desfavoritar ${displayBusiness.name}'
                    : 'Favoritar ${displayBusiness.name}',
                onPressed: onFavorite,
                icon: Icon(
                  saved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
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
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(3),
              child: Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.orange, AppColors.sky],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (previewMode) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
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
                  _buildBusinessHero(context),
                  const SizedBox(height: 14),
                  _buildBusinessSummary(context),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildBusinessActions(context, actions),
                  ],
                  if (displayBusiness.services.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InfoBlock(
                      title: 'Serviços',
                      text: displayBusiness.services
                          .map((item) => '• $item')
                          .join('\n'),
                    ),
                  ],
                  if (displayBusiness.products.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InfoBlock(
                      title: 'Produtos',
                      text: displayBusiness.products
                          .map((item) => '• $item')
                          .join('\n'),
                    ),
                  ],
                  if (displayBusiness.hours.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    BusinessHoursInfo(
                      hours: displayBusiness.hours,
                      fallbackSpecified: displayBusiness.statusSpecified,
                      fallbackOpen: displayBusiness.open,
                      clock: openingStatusClock,
                    ),
                  ],
                  if (displayBusiness.additionalInfo.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InfoBlock(
                      title: 'Informações adicionais',
                      text: displayBusiness.additionalInfo,
                    ),
                  ],
                  if (displayBusiness.promotionTitle.isNotEmpty) ...[
                    const SizedBox(height: 12),
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
                            displayBusiness.promotionTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          if (displayBusiness
                              .promotionDescription
                              .isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              displayBusiness.promotionDescription,
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

  Widget _buildBusinessHero(BuildContext context) {
    if (!showPremiumContent) {
      return Container(
        key: const ValueKey('business-profile-basic-hero'),
        width: double.infinity,
        height: 196,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.cardLarge),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.ocean, AppColors.sky],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.ocean.withValues(alpha: .16),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Icon(Icons.storefront_rounded, color: Colors.white, size: 34),
            const SizedBox(height: 12),
            Text(
              displayBusiness.name,
              key: const ValueKey('business-profile-name'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.08,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              displayBusiness.categoryLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: .94),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    final imageCount = displayBusiness.displayImageUrls.length;
    final hasLogo = displayBusiness.logoUrl.trim().isNotEmpty;
    return Container(
      key: const ValueKey('business-profile-hero'),
      height: 238,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.cardLarge),
        boxShadow: [
          BoxShadow(
            color: AppColors.ocean.withValues(alpha: .16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.cardLarge),
        child: Stack(
          fit: StackFit.expand,
          children: [
            BusinessHeroMedia(
              business: displayBusiness,
              useLogoFallback: false,
            ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x18001835),
                      Color(0x00101820),
                      Color(0xCC061B32),
                    ],
                    stops: [0, .38, 1],
                  ),
                ),
              ),
            ),
            if (imageCount > 1)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  key: const ValueKey('business-profile-gallery-count'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.ink.withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$imageCount fotos',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (hasLogo) ...[
                    Container(
                      key: const ValueKey('business-profile-logo-overlap'),
                      width: 68,
                      height: 68,
                      clipBehavior: Clip.antiAlias,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .86),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: .2),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: BusinessAvatar(
                          business: displayBusiness,
                          size: 62,
                          iconFallback: const Icon(
                            Icons.storefront_rounded,
                            color: AppColors.ocean,
                            size: 38,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayBusiness.name,
                          key: const ValueKey('business-profile-name'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: 1.08,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x80000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          displayBusiness.categoryLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: .94),
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x80000000),
                                    blurRadius: 6,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessSummary(BuildContext context) => Card(
    key: const ValueKey('business-profile-summary'),
    margin: EdgeInsets.zero,
    elevation: 1,
    shadowColor: AppColors.ocean.withValues(alpha: .07),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: BorderSide(color: AppColors.ocean.withValues(alpha: .07)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.orange,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    displayBusiness.location,
                    key: const ValueKey('business-profile-location'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (showPremiumContent &&
              displayBusiness.statusSpecified &&
              displayBusiness.hours.isEmpty) ...[
            const SizedBox(height: 12),
            MiniLabel(
              text: displayBusiness.open
                  ? 'Status informado: aberto'
                  : 'Status informado: fechado',
              color: displayBusiness.open
                  ? const Color(0xFF1E9662)
                  : AppColors.muted,
            ),
          ],
          if (showPremiumContent &&
              displayBusiness.description.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: AppColors.ocean.withValues(alpha: .08), height: 1),
            const SizedBox(height: 12),
            Text(
              'Sobre',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              displayBusiness.description,
              key: const ValueKey('business-profile-description'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
          ],
          if (!showPremiumContent &&
              displayBusiness.phone.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: AppColors.ocean.withValues(alpha: .08), height: 1),
            const SizedBox(height: 12),
            Text(
              'Telefone',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            SelectableText(
              displayBusiness.phone,
              key: const ValueKey('business-profile-basic-phone'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _buildBusinessActions(
    BuildContext context,
    List<_BusinessAction> actions,
  ) => Card(
    key: const ValueKey('business-profile-actions'),
    margin: EdgeInsets.zero,
    elevation: 1,
    shadowColor: AppColors.ocean.withValues(alpha: .07),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: BorderSide(color: AppColors.ocean.withValues(alpha: .07)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.skyTint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.touch_app_rounded,
                  color: AppColors.ocean,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Contato e acesso',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            key: const ValueKey('business-actions-grid'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.textScalerOf(context).scale(1) >= 1.4
                  ? 1
                  : 2,
              crossAxisSpacing: 9,
              mainAxisSpacing: 9,
              mainAxisExtent:
                  (64 * MediaQuery.textScalerOf(context).scale(14) / 14)
                      .clamp(64.0, 112.0)
                      .toDouble(),
            ),
            itemBuilder: (context, index) {
              final item = actions[index];
              return BusinessActionButton(
                key: item.key,
                icon: item.icon,
                title: item.title,
                subtitle: item.subtitle,
                gradientColors: item.colors,
                onPressed: () => openBusinessAction(
                  context,
                  displayBusiness,
                  action: item.action,
                  url: item.url,
                  label: item.label,
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// Public detail route. The Basic profile is rendered immediately; a single
/// Premium sibling read may enrich this screen. Any unavailable, denied,
/// missing, invalid, or expired result leaves the Basic profile untouched.
class PublicBusinessProfile extends StatefulWidget {
  const PublicBusinessProfile({
    super.key,
    required this.business,
    required this.saved,
    required this.onFavorite,
    this.repository,
    this.canEdit = false,
    this.onEdit,
    this.trackShareMetric = true,
    this.openingStatusClock,
  });

  final Business business;
  final bool saved;
  final VoidCallback onFavorite;
  final BusinessRepository? repository;
  final bool canEdit;
  final VoidCallback? onEdit;
  final bool trackShareMetric;
  final DateTime Function()? openingStatusClock;

  @override
  State<PublicBusinessProfile> createState() => _PublicBusinessProfileState();
}

class _PublicBusinessProfileState extends State<PublicBusinessProfile> {
  Business? _premiumBusiness;
  Timer? _expiryTimer;

  Business get _visibleBusiness {
    final premium = _premiumBusiness;
    if (premium == null || !premium.isPremiumEffectiveAt(DateTime.now())) {
      return widget.business.asBasicProjection();
    }
    return premium;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.business;
    if (existing.isPremiumEffectiveAt(DateTime.now())) {
      _premiumBusiness = existing;
      _scheduleExpiry(existing.premiumUntil!);
    } else {
      unawaited(_loadPremium());
    }
  }

  @override
  void didUpdateWidget(covariant PublicBusinessProfile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.business.id != widget.business.id) {
      _expiryTimer?.cancel();
      _premiumBusiness = null;
      if (widget.business.isPremiumEffectiveAt(DateTime.now())) {
        _premiumBusiness = widget.business;
        _scheduleExpiry(widget.business.premiumUntil!);
      } else {
        unawaited(_loadPremium());
      }
    }
  }

  Future<void> _loadPremium() async {
    final basic = widget.business.asBasicProjection();
    if (basic.id.isEmpty ||
        widget.business.listingTier == ListingTier.premium &&
            widget.business.isPremiumEffectiveAt(DateTime.now())) {
      return;
    }
    final result = await (widget.repository ?? BusinessRepository())
        .getPremiumProjectionForBasic(basic.id);
    final expiry = result.premiumUntil;
    if (!mounted ||
        widget.business.id != basic.id ||
        !result.isAvailable ||
        expiry == null ||
        !expiry.isAfter(DateTime.now().toUtc())) {
      return;
    }
    final enriched = basic.withPremiumProjection(
      result.data,
      premiumUntil: expiry,
    );
    setState(() => _premiumBusiness = enriched);
    _scheduleExpiry(expiry);
  }

  void _scheduleExpiry(DateTime expiry) {
    _expiryTimer?.cancel();
    final remaining = expiry.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      _premiumBusiness = null;
      return;
    }
    _expiryTimer = Timer(remaining, () {
      if (mounted) setState(() => _premiumBusiness = null);
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BusinessProfile(
    business: _visibleBusiness,
    saved: widget.saved,
    onFavorite: widget.onFavorite,
    canEdit: widget.canEdit,
    onEdit: widget.onEdit,
    trackShareMetric: widget.trackShareMetric,
    openingStatusClock: widget.openingStatusClock,
  );
}
