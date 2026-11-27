import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

const macacuCitySlogan = 'Cidade das Águas Cristalinas';
const tudoAquiAppSlogan = 'A cidade na sua mão.';

/// Shared Tudo Aqui Macacu wordmark and original location symbol.
class AppBrand extends StatelessWidget {
  const AppBrand({
    super.key,
    this.logoUrl = '',
    this.tagline = tudoAquiAppSlogan,
    this.inverse = false,
    this.compact = false,
  });

  final String logoUrl;
  final String tagline;
  final bool inverse;
  final bool compact;

  static const _assetPath = 'assets/images/tudo-aqui-macacu-mark-transparent.png';

  @override
  Widget build(BuildContext context) {
    final markSize = compact ? 34.0 : 44.0;
    final titleColor = inverse ? Colors.white : AppColors.ink;
    final accentColor = inverse ? AppColors.orange : AppColors.ocean;
    final effectiveTagline = compact ? '' : tagline.trim();
    final textTheme = Theme.of(context).textTheme;
    final brandLabel = effectiveTagline.isEmpty
        ? 'Tudo Aqui Macacu'
        : 'Tudo Aqui Macacu. $effectiveTagline';

    return Semantics(
      container: true,
      label: brandLabel,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 156 : 292),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BrandMark(
                size: markSize,
                logoUrl: logoUrl,
                assetPath: _assetPath,
              ),
              SizedBox(width: compact ? 7 : 9),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tudo Aqui',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(
                        color: titleColor,
                        height: 1.02,
                        fontSize: compact ? 10 : 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Macacu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: accentColor,
                        height: 1.04,
                        fontSize: compact ? 15 : 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (effectiveTagline.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        effectiveTagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: inverse ? Colors.white70 : AppColors.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({
    required this.size,
    required this.logoUrl,
    required this.assetPath,
  });

  final double size;
  final String logoUrl;
  final String assetPath;

  Widget _localLogo() => Image.asset(
    assetPath,
    key: const ValueKey('app-brand-logo-local'),
    width: size,
    height: size,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const ColoredBox(
      color: AppColors.ocean,
      child: Icon(Icons.location_on_rounded, color: AppColors.orange),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final remoteUrl = logoUrl.trim();
    return SizedBox.square(
      dimension: size,
      child: remoteUrl.isEmpty
          ? _localLogo()
          : Image.network(
              remoteUrl,
              key: const ValueKey('app-brand-logo-remote'),
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _localLogo(),
            ),
    );
  }
}
