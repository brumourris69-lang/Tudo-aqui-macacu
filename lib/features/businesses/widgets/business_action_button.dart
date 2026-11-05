import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A compact, branded action tile used on public business details.
class BusinessActionButton extends StatefulWidget {
  const BusinessActionButton({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final VoidCallback onPressed;

  @override
  State<BusinessActionButton> createState() => _BusinessActionButtonState();
}

class _BusinessActionButtonState extends State<BusinessActionButton> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? .985 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Semantics(
        button: true,
        label: '${widget.title}. ${widget.subtitle}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: widget.onPressed,
            onHighlightChanged: (value) {
              if (_pressed != value) setState(() => _pressed = value);
            },
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                gradient: LinearGradient(
                  colors: widget.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .52)),
                boxShadow: [
                  BoxShadow(
                    color: widget.gradientColors.last.withValues(alpha: .19),
                    blurRadius: 7,
                    offset: const Offset(0, 3),
                  ),
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: .06),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                    child: Row(
                      children: [
                        Icon(widget.icon, color: Colors.white, size: 24),
                        const SizedBox(width: 3),
                        Container(
                          width: 1,
                          height: 27,
                          color: Colors.white.withValues(alpha: .48),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final textScale = MediaQuery.textScalerOf(
                                context,
                              ).scale(1);
                              final compact = constraints.maxWidth < 112;
                              final title =
                                  compact && widget.title.contains(' ')
                                  ? widget.title.replaceFirst(' ', '\n')
                                  : widget.title;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    softWrap: true,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: compact ? 12 : 13.5,
                                      height: 1.05,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.subtitle,
                                    maxLines: textScale > 1.15 ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: .92,
                                      ),
                                      fontSize: 10.5,
                                      height: 1.05,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 2,
                    left: 14,
                    right: 14,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1),
                        color: Colors.white.withValues(alpha: .42),
                      ),
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
}
