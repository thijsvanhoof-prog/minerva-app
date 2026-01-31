import 'package:flutter/material.dart';
import 'package:minerva_app/ui/app_colors.dart';

/// A dark blue box with orange text for section titles.
/// Used throughout the app for better readability on the busy background.
class SectionTitleBox extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final TextStyle? titleStyle;

  const SectionTitleBox({
    super.key,
    required this.title,
    this.trailing,
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkBlue,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: titleStyle ??
                  Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                      ),
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}
