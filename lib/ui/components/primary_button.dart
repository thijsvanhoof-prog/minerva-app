import 'package:flutter/material.dart';

import 'package:minerva_app/ui/app_colors.dart';

/// A branded primary call-to-action button (orange gradient).
class PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool loading;

  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;

    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: enabled
                  ? const [Color(0xFFFF8A00), Color(0xFFE67A00)]
                  : [
                      AppColors.primary.withValues(alpha: 0.45),
                      AppColors.primary.withValues(alpha: 0.25),
                    ],
            ),
          ),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: loading
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.background,
                      ),
                    )
                  : DefaultTextStyle.merge(
                      key: const ValueKey('child'),
                      style: const TextStyle(
                        color: AppColors.background,
                        fontWeight: FontWeight.w800,
                      ),
                      child: child,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

