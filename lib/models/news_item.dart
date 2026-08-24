/// Een link bij een nieuwsbericht (url + optioneel label).
class NewsLink {
  final String url;
  final String? label;

  const NewsLink({required this.url, this.label});

  String get displayLabel => (label != null && label!.trim().isNotEmpty)
      ? label!.trim()
      : _shortUrl(url);

  static String _shortUrl(String url) {
    final u = url.trim();
    if (u.length <= 45) return u;
    return '${u.substring(0, 42)}…';
  }
}

class NewsItem {
  final String id;
  final String title;
  final String body;
  final DateTime date;
  final String author;
  final NewsCategory category;
  final bool pinned;
  final DateTime? visibleUntil;
  /// URL's van afbeeldingen (Supabase Storage of externe URLs).
  final List<String> imageUrls;
  /// Linkjes bij het bericht (url + optioneel label).
  final List<NewsLink> links;

  const NewsItem({
    required this.id,
    required this.title,
    required this.body,
    required this.date,
    required this.author,
    required this.category,
    this.pinned = false,
    this.visibleUntil,
    this.imageUrls = const [],
    this.links = const [],
  });
}

enum NewsCategory { bestuur, tc, communicatie, team }

extension NewsCategoryX on NewsCategory {
  String get label {
    switch (this) {
      case NewsCategory.bestuur:
        return 'Bestuur';
      case NewsCategory.tc:
        return 'Technische Commissie';
      case NewsCategory.communicatie:
        return 'Communicatie';
      case NewsCategory.team:
        return 'Team';
    }
  }
}
