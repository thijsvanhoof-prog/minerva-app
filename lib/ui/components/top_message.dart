import 'dart:async';

import 'package:flutter/material.dart';

import 'package:minerva_app/ui/app_colors.dart';

void showTopMessage(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  showTopMessageWithMessenger(messenger, message, isError: isError, duration: duration);
}

/// Toon een bericht via de gegeven messenger. Gebruik dit na async gaps
/// in plaats van context, om BuildContext-across-async-gaps te vermijden.
void showTopMessageWithMessenger(
  ScaffoldMessengerState messenger,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 4),
}) {
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

