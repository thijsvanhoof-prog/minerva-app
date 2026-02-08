import '../models/news_item.dart';

final mockNews = <NewsItem>[
  NewsItem(
    id: '1',
    title: 'Nieuwjaarsborrel: datum bekend',
    body: 'Vrijdag 10 januari organiseren we de nieuwjaarsborrel in de kantine. '
        'Alle leden, trainers en vrijwilligers zijn welkom. Aanvang 20:00.',
    date: DateTime.now().subtract(const Duration(hours: 3)),
    author: 'Bestuur',
    category: NewsCategory.bestuur,
    pinned: true,
    visibleUntil: null,
  ),
  NewsItem(
    id: '2',
    title: 'Teamindeling jeugd (update)',
    body: 'De voorlopige teamindeling is bijgewerkt. Trainers nemen deze week '
        'contact op voor het eerste trainingsmoment.',
    date: DateTime.now().subtract(const Duration(days: 1)),
    author: 'TC',
    category: NewsCategory.tc,
    visibleUntil: null,
  ),
  NewsItem(
    id: '3',
    title: 'Foto’s van het toernooi staan online',
    body: 'De foto’s van het minitoernooi staan in het album. Dank aan alle helpers!',
    date: DateTime.now().subtract(const Duration(days: 2)),
    author: 'Communicatie',
    category: NewsCategory.communicatie,
    visibleUntil: null,
  ),
];

class HighlightItem {
  final String title;
  final String subtitle;
  final String icon; // simpele emoji/tekst placeholder; later vervangen door icons of images

  const HighlightItem({required this.title, required this.subtitle, required this.icon});
}

final mockHighlights = <HighlightItem>[
  const HighlightItem(title: 'Volgende wedstrijd', subtitle: 'Heren 2 – 20:30 (Dillenburcht)', icon: '🏐'),
  const HighlightItem(title: 'Training vanavond', subtitle: 'Jeugd A – 18:00 (Vlijmen)', icon: '⏱'),
  const HighlightItem(title: 'Evenement', subtitle: 'Clubdag – inschrijving open', icon: '📌'),
];