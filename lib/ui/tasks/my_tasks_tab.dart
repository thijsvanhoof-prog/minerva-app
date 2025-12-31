import 'package:flutter/material.dart';
import '../app_colors.dart';

class MyTasksTab extends StatelessWidget {
  const MyTasksTab({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = _mockTasks();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mijn taken'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Jouw verenigingstaken',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Overzicht van fluitbeurten, tellingen, kantinediensten.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ...tasks.map((t) => _TaskCard(task: t)),
        ],
      ),
    );
  }
}

/* ===================== UI ===================== */

class _TaskCard extends StatelessWidget {
  final _Task task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    // CardTheme in AppUi regelt: kleur + rand + radius + dikte
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                task.icon,
                color: task.required ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.onBackground,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      task.subtitle,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {},
                        child: const Text('Bekijk details'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ===================== DATA ===================== */

class _Task {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool required;

  const _Task({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.required,
  });
}

List<_Task> _mockTasks() => const [
      _Task(
        icon: Icons.sports,
        title: 'Fluiten – Heren 2',
        subtitle: 'Za 3 feb • 14:30 • Veld 2',
        required: true,
      ),
      _Task(
        icon: Icons.calculate,
        title: 'Tellen – Dames 1',
        subtitle: 'Za 10 feb • 16:00',
        required: true,
      ),
      _Task(
        icon: Icons.local_cafe,
        title: 'Kantinedienst',
        subtitle: 'Zo 18 feb • 12:00 – 14:00',
        required: false,
      ),
      _Task(
        icon: Icons.assignment,
        title: 'Enquête jeugdbeleid',
        subtitle: 'Invullen vóór 1 maart',
        required: false,
      ),
    ];