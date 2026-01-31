import 'package:flutter/material.dart';

/// AppBar title that shows the Minerva logo.
///
/// If the asset is missing, we fall back to the text "Minerva" so the app
/// never crashes during development.
class AppLogoTitle extends StatelessWidget {
  final double height;

  const AppLogoTitle({super.key, this.height = 28});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/minerva_logo.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        return Text(
          'Minerva',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        );
      },
    );
  }
}
