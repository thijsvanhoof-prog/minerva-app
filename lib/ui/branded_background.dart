import 'package:flutter/material.dart';

/// Global branded background used behind main tabs.
///
/// Uses the exact background image (flowing waves in navy, orange, white).
class BrandedBackground extends StatelessWidget {
  final Widget child;

  const BrandedBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image
        IgnorePointer(
          child: Image.asset(
            'assets/branding/background.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              return const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFFFFFFF)),
              );
            },
          ),
        ),
        child,
      ],
    );
  }
}
