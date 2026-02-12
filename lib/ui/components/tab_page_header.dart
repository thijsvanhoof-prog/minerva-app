import 'package:flutter/material.dart';

import 'package:minerva_app/ui/app_colors.dart';

/// Donkerblauwe header die doorloopt vanuit de statusbalk.
/// Gebruik bovenaan elke tab-pagina voor een consistente look.
class TabPageHeader extends StatelessWidget {
  final Widget child;

  const TabPageHeader({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, topPadding + 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.darkBlue,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppColors.cardRadius),
          bottomRight: Radius.circular(AppColors.cardRadius),
        ),
      ),
      child: child,
    );
  }
}
