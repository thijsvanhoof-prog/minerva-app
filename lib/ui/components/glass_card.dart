import 'dart:ui';

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

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.borderRadius = AppColors.cardRadius,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(borderRadius);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: r,
        color: AppColors.card,
        border: Border.all(
          color: const Color(0xFF1A2B4A).withValues(alpha: 0.15),
          width: AppColors.cardBorderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A2B4A).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Container(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

