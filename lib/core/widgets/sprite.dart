import 'package:flutter/material.dart';

const _legacySpriteAssetPaths = <String>[
  'assets/images/icons/01_comercio.png',
  'assets/images/icons/02_onde_comer.png',
  'assets/images/icons/03_servicos.png',
  'assets/images/icons/03_servicos.png',
  'assets/images/icons/07_empregos.png',
  'assets/images/icons/04_turismo.png',
  'assets/images/icons/09_noticias.png',
  'assets/images/icons/08_eventos.png',
  'assets/images/icons/05_saude.png',
  'assets/images/icons/25_imoveis.png',
  'assets/images/icons/26_transporte.png',
  'assets/images/icons/22_pets.png',
  'assets/images/icons/21_beleza.png',
  'assets/images/icons/23_academia.png',
  'assets/images/icons/06_educacao.png',
  'assets/images/icons/24_hospedagem.png',
  'assets/images/icons/11_cupons.png',
  'assets/images/icons/10_utilidades.png',
];

class Sprite extends StatelessWidget {
  const Sprite({super.key, required this.index, this.size = 56});

  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final safeIndex = _safeLegacySpriteIndex(index);
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        _legacySpriteAssetPaths[safeIndex],
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => LegacySprite(index: safeIndex, size: size),
      ),
    );
  }
}

int _safeLegacySpriteIndex(int index) {
  if (index >= 0 && index < _legacySpriteAssetPaths.length) return index;
  debugPrint(
    'Índice legado de ícone inválido: $index. Usando fallback serviços.',
  );
  return 2;
}

class LegacySprite extends StatelessWidget {
  const LegacySprite({super.key, required this.index, this.size = 56});

  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final safeIndex = index.clamp(0, 17);
    final col = safeIndex % 6;
    final row = safeIndex ~/ 6;
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * .23),
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: size * 6,
          maxWidth: size * 6,
          minHeight: size * 3,
          maxHeight: size * 3,
          child: Transform.translate(
            offset: Offset(-col * size, -row * size),
            child: Image.asset(
              'assets/images/category-icons-3d.png',
              width: size * 6,
              height: size * 3,
              fit: BoxFit.fill,
            ),
          ),
        ),
      ),
    );
  }
}
