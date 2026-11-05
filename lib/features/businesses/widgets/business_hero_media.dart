import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/business.dart';

class BusinessHeroMedia extends StatefulWidget {
  const BusinessHeroMedia({
    super.key,
    required this.business,
    this.useLogoFallback = true,
  });

  final Business business;
  final bool useLogoFallback;

  @override
  State<BusinessHeroMedia> createState() => _BusinessHeroMediaState();
}

class _BusinessHeroMediaState extends State<BusinessHeroMedia> {
  final controller = PageController();
  var page = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.business.displayImageUrls;
    final logoUrl = widget.business.logoUrl.trim();
    final showHeroLogo = widget.useLogoFallback && logoUrl.isNotEmpty;
    return Semantics(
      label: images.isEmpty
          ? !showHeroLogo
                ? 'Imagem de ${widget.business.name}'
                : 'Logo de ${widget.business.name}'
          : 'Galeria de ${widget.business.name}, imagem ${page + 1} de ${images.length}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (images.isEmpty)
            showHeroLogo
                ? Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.ocean, AppColors.sky],
                      ),
                    ),
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ColoredBox(
                          color: Colors.white,
                          child: SizedBox(
                            width: 160,
                            height: 160,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Image.network(
                                logoUrl,
                                key: const ValueKey('business-hero-logo'),
                                fit: BoxFit.contain,
                                loadingBuilder: (_, child, progress) =>
                                    progress == null
                                    ? child
                                    : const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.ocean,
                                          ),
                                        ),
                                      ),
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(
                                    Icons.storefront_outlined,
                                    size: 56,
                                    color: AppColors.ocean,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : widget.business.category == 'Turismo'
                ? Image.asset(
                    'assets/images/macacu-waterfall-hero.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _heroPlaceholder(),
                  )
                : _heroPlaceholder()
          else
            PageView.builder(
              controller: controller,
              itemCount: images.length,
              onPageChanged: (value) => setState(() => page = value),
              itemBuilder: (_, index) => Image.network(
                images[index],
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        color: AppColors.ocean,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                errorBuilder: (_, _, _) => _heroPlaceholder(),
              ),
            ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x66101820), Color(0x00101820)],
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                ),
              ),
            ),
          ),
          if (images.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  images.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: index == page ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _heroPlaceholder() => Container(
    key: const ValueKey('business-hero-placeholder'),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.ocean, AppColors.sky],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ),
    ),
    child: Center(
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: .2)),
        ),
        child: const Icon(
          Icons.storefront_rounded,
          size: 46,
          color: Colors.white70,
        ),
      ),
    ),
  );
}
