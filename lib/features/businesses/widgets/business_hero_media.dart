import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/business.dart';

class BusinessHeroMedia extends StatefulWidget {
  const BusinessHeroMedia({super.key, required this.business});

  final Business business;

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
    final images = widget.business.galleryUrls.isEmpty
        ? (widget.business.imageUrl.isEmpty
              ? const <String>[]
              : [widget.business.imageUrl])
        : widget.business.galleryUrls;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (images.isEmpty)
          widget.business.category == 'Turismo'
              ? Image.asset(
                  'assets/images/macacu-waterfall-hero.png',
                  fit: BoxFit.cover,
                )
              : Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.ocean, AppColors.sky],
                    ),
                  ),
                )
        else
          PageView.builder(
            controller: controller,
            itemCount: images.length,
            onPageChanged: (value) => setState(() => page = value),
            itemBuilder: (_, index) => Image.network(
              images[index],
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.ocean, AppColors.sky],
                  ),
                ),
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x66101820), Color(0x00101820)],
              begin: Alignment.topCenter,
              end: Alignment.center,
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
    );
  }
}
