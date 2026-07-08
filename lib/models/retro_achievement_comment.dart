/// A comment posted on a RetroAchievements achievement page.
class RetroAchievementComment {
  final String user;
  final String ulid;
  final DateTime? submitted;
  final String commentText;

  const RetroAchievementComment({
    required this.user,
    required this.ulid,
    required this.submitted,
    required this.commentText,
  });

  factory RetroAchievementComment.fromJson(Map<String, dynamic> json) {
    return RetroAchievementComment(
      user: (json['User'] ?? '').toString(),
      ulid: (json['ULID'] ?? '').toString(),
      submitted: DateTime.tryParse((json['Submitted'] ?? '').toString()),
      commentText: (json['CommentText'] ?? '').toString(),
    );
  }

  /// Stable enough for de-duplicating overlapping API pages.
  String get cacheKey => '$ulid|${submitted?.toIso8601String()}|$commentText';

  bool get isSystemComment {
    final normalized = user.trim().toLowerCase();
    return normalized == 'system' || normalized == 'server';
  }
}

class RetroAchievementCommentsPage {
  final int count;
  final int total;
  final List<RetroAchievementComment> results;

  const RetroAchievementCommentsPage({
    required this.count,
    required this.total,
    required this.results,
  });

  factory RetroAchievementCommentsPage.fromJson(Map<String, dynamic> json) {
    final rawResults = json['Results'];
    return RetroAchievementCommentsPage(
      count: _toInt(json['Count']),
      total: _toInt(json['Total']),
      results: rawResults is List
          ? rawResults
                .whereType<Map>()
                .map(
                  (item) => RetroAchievementComment.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where((comment) => !comment.isSystemComment)
                .toList()
          : const [],
    );
  }

  static int _toInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
