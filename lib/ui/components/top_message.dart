import 'dart:async';

import 'package:flutter/material.dart';

import 'package:minerva_app/ui/app_colors.dart';

void showTopMessage(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.of(context);

  // Avoid stacking multiple banners/snackbars.
  messenger.clearSnackBars();
  messenger.hideCurrentMaterialBanner();

  Timer? timer;
  void close() {
    timer?.cancel();
    messenger.hideCurrentMaterialBanner();
  }

  messenger.showMaterialBanner(
    MaterialBanner(
      backgroundColor: AppColors.darkBlue.withValues(alpha: 0.97),
      leading: Icon(
        isError ? Icons.error_outline : Icons.info_outline,
        color: isError ? AppColors.error : AppColors.primary,
      ),
      content: Text(
        message,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      actions: [
        TextButton(
          onPressed: close,
          child: const Text('Sluiten'),
        ),
      ],
    ),
  );

  timer = Timer(duration, close);
}

