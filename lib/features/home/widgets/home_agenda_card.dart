import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Compact presentation of the existing published event data on the Home.
class HomeAgendaCard extends StatelessWidget {
  const HomeAgendaCard({
    super.key,
    required this.title,
    required this.onTap,
    this.date,
    this.location = '',
    this.category = '',
    this.imageUrl = '',
    this.loading = false,
  });

  final String title, location, category, imageUrl;
  final DateTime? date;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: AppColors.ink.withValues(alpha: .045),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Container(
                  width: 62,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5E8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: date == null
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Icon(
                            Icons.event_rounded,
                            color: AppColors.orange,
                            size: 26,
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${date!.day}',
                              maxLines: 1,
                              style: const TextStyle(
                                color: AppColors.orange,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              const [
                                'JAN',
                                'FEV',
                                'MAR',
                                'ABR',
                                'MAI',
                                'JUN',
                                'JUL',
                                'AGO',
                                'SET',
                                'OUT',
                                'NOV',
                                'DEZ',
                              ][date!.month - 1],
                              maxLines: 1,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .7,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1, right: 4),
                              child: Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: AppColors.muted,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                location,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (category.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDF5FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.ocean,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (imageUrl.isNotEmpty && constraints.maxWidth >= 340) ...[
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageUrl,
                      width: 48,
                      height: 58,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                Container(
                  width: 32,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDF5FF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: loading
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.calendar_month_rounded,
                          color: AppColors.sky,
                          size: 20,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
