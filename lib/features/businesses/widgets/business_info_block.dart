import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class InfoBlock extends StatelessWidget {
  const InfoBlock({super.key, required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 19),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          style: const TextStyle(color: AppColors.muted, height: 1.45),
        ),
      ],
    ),
  );
}
