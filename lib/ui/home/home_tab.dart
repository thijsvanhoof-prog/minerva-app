import 'package:flutter/material.dart';

import '../app_colors.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final highlights = _mockHighlights();
    final agendaItems = _mockAgenda();
    final newsItems = _mockNews();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Minerva'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Welkom bij VV Minerva',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Updates, agenda en nieuws vanuit de vereniging.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),

          const _SectionTitle('Uitgelicht'),
          const SizedBox(height: 12),
          SizedBox(
            height: 135,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: highlights.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => SizedBox(
                width: 260,
                child: _HighlightCard(item: highlights[i]),
              ),
            ),
          ),

          const SizedBox(height: 22),
          const _SectionTitle('Agenda'),
          const SizedBox(height: 12),
          ...agendaItems.map((a) => _AgendaCard(item: a)),

          const SizedBox(height: 22),
          const _SectionTitle('Nieuwsberichten'),
          const SizedBox(height: 12),
          ...newsItems.map((n) => _NewsCard(item: n)),
        ],
      ),
    );
  }
}

/* ----------------------- SHARED UI ----------------------- */

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

class _CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const _CardBox({
    required this.child,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.65),
          width: 2.2, // vaste dikke oranje rand
        ),
      ),
      child: child,
    );
  }
}

/* ----------------------- HIGHLIGHTS ----------------------- */

class _HighlightCard extends StatelessWidget {
  final _Highlight item;
  const _HighlightCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: AppColors.primary, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.subtitle,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ----------------------- AGENDA ----------------------- */

class _AgendaCard extends StatelessWidget {
  final _AgendaItem item;
  const _AgendaCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.calendar_month, color: AppColors.primary),
        title: Text(
          item.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: Text(
          '${item.when} • ${item.where}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        trailing: item.canRsvp
            ? FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                ),
                onPressed: () {},
                child: const Text('Aanmelden'),
              )
            : null,
      ),
    );
  }
}

/* ----------------------- NIEUWS ----------------------- */

class _NewsCard extends StatelessWidget {
  final _NewsItem item;
  const _NewsCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(item.source),
              _Pill(item.author),
              Text(
                item.dateLabel,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            item.body,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
              onPressed: () {},
              child: const Text('Lees meer'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.45),
          width: 1.4,
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.onBackground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

/* ----------------------- MOCK DATA ----------------------- */

class _Highlight {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Highlight(this.icon, this.title, this.subtitle);
}

class _AgendaItem {
  final String title;
  final String when;
  final String where;
  final bool canRsvp;
  const _AgendaItem(this.title, this.when, this.where, this.canRsvp);
}

class _NewsItem {
  final String source;
  final String author;
  final String dateLabel;
  final String title;
  final String body;
  const _NewsItem(
    this.source,
    this.author,
    this.dateLabel,
    this.title,
    this.body,
  );
}

List<_Highlight> _mockHighlights() => const [
      _Highlight(Icons.campaign, 'Seizoensstart',
          'Belangrijke clubafspraken en planning'),
      _Highlight(Icons.emoji_events, 'Toernooi',
          'Inschrijving geopend (jeugd & senioren)'),
      _Highlight(Icons.volunteer_activism, 'Vrijwilligers gezocht',
          'Tafelaars en scheidsrechters nodig'),
    ];

List<_AgendaItem> _mockAgenda() => const [
      _AgendaItem('Algemene ledenvergadering', 'Ma 15 jan • 20:00', 'Kantine', false),
      _AgendaItem('Clubdag', 'Za 10 feb • 10:00', 'Sporthal', true),
    ];

List<_NewsItem> _mockNews() => const [
      _NewsItem(
        'Bestuur',
        'Bestuur',
        'Vandaag',
        'Update vanuit het bestuur',
        'Korte mededeling over de komende periode.',
      ),
      _NewsItem(
        'Technische Commissie',
        'TC',
        'Gisteren',
        'Teamindelingen en trainers',
        'Overzicht van wijzigingen binnen de teams.',
      ),
    ];