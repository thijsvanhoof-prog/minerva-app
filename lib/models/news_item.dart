class NewsItem {
  final String id;
  final String title;
  final String body;
  final DateTime date;
  final String author;
  final NewsCategory category;
  final bool pinned;
  final DateTime? visibleUntil;

  const NewsItem({
    required this.id,
    required this.title,
    required this.body,
    required this.date,
    required this.author,
    required this.category,
    this.pinned = false,
    this.visibleUntil,
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