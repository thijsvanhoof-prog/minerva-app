import 'package:flutter/material.dart';

import 'package:minerva_app/ui/app_colors.dart';

/// A lightweight "glass" card (glassmorphism).
///
/// Used throughout the app to create a modern, cheerful but professional look.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final bool showBorder;
  final bool showShadow;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.borderRadius = AppColors.cardRadius,
    this.showBorder = true,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(borderRadius);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: r,
        color: AppColors.card,
        border: showBorder
            ? Border.all(
                color: AppColors.primary.withValues(alpha: 0.55),
                width: AppColors.cardBorderWidth,
              )
            : null,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: AppColors.darkBlue.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Container(
          decoration: showBorder
              ? BoxDecoration(
                  borderRadius: r,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    width: 1,
                  ),
                )
              : null,
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

