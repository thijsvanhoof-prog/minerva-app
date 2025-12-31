import 'package:flutter/material.dart';

import '../app_colors.dart';

class InfoTab extends StatelessWidget {
  const InfoTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Info'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _InfoCard(
            icon: Icons.info_outline,
            title: 'Over de app',
            subtitle:
                'Deze app helpt je bij trainingen, wedstrijden en verenigingszaken.',
          ),
          SizedBox(height: 12),
          _InfoCard(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy',
            subtitle:
                'Je gegevens worden alleen gebruikt binnen de vereniging.',
          ),
          SizedBox(height: 12),
          _InfoCard(
            icon: Icons.support_agent,
            title: 'Contact',
            subtitle:
                'Vragen of problemen? Neem contact op met het bestuur.',
          ),
        ],
      ),
    );
  }
}

/* ===================== UI ===================== */

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.onBackground,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}