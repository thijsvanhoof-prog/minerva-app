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
  showTopMessageWithMessenger(messenger, message, isError: isError, duration: duration, overlayContext: context);
}

/// Toon een bericht via de gegeven messenger. Gebruik dit na async gaps
/// in plaats van context, om BuildContext-across-async-gaps te vermijden.
/// Geef [overlayContext] mee (bijv. uit showTopMessage) zodat de melding onder de koptekst komt;
/// anders valt de melding terug op MaterialBanner bovenaan.
void showTopMessageWithMessenger(
  ScaffoldMessengerState messenger,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 4),
  BuildContext? overlayContext,
}) {
  messenger.clearSnackBars();
  messenger.hideCurrentMaterialBanner();

  // Overlay zit in de Navigator; messenger.context is er vaak boven. Gebruik overlayContext als die is meegegeven.
  final contextForOverlay = overlayContext ?? messenger.context;
  final overlay = Overlay.maybeOf(contextForOverlay);

  if (overlay != null) {
    final topInset = MediaQuery.paddingOf(contextForOverlay).top;
    const headerHeight = 88.0;
    final topOffset = topInset + headerHeight;

    OverlayEntry? entry;
    void close() {
      entry?.remove();
      entry = null;
    }

    Timer? timer;
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: topOffset,
        left: 12,
        right: 12,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          color: AppColors.darkBlue,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.info_outline,
                  color: isError ? AppColors.error : AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    timer?.cancel();
                    close();
                  },
                  child: const Text('Sluiten'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    entry = overlayEntry;
    overlay.insert(overlayEntry);
    timer = Timer(duration, () {
      timer?.cancel();
      close();
    });
    return;
  }

  // Fallback: geen overlay (bijv. alleen messenger na async) → MaterialBanner bovenaan
  Timer? timer;
  void close() {
    timer?.cancel();
    messenger.hideCurrentMaterialBanner();
  }
  messenger.showMaterialBanner(
    MaterialBanner(
      backgroundColor: AppColors.darkBlue,
      leading: Icon(
        isError ? Icons.error_outline : Icons.info_outline,
        color: isError ? AppColors.error : AppColors.primary,
      ),
      content: Text(
        message,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      actions: [
        TextButton(onPressed: close, child: const Text('Sluiten')),
      ],
    ),
  );
  timer = Timer(duration, close);
}

