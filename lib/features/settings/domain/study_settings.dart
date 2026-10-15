/// Global defaults applied independently to each card's owning deck.
class StudySettings {
  StudySettings({
    this.dailyNewLimit = 20,
    this.dailyReviewLimit = 200,
    this.desiredRetentionPercent = 90,
  }) {
    if (dailyNewLimit < 0 || dailyNewLimit > 9999) {
      throw ArgumentError('每日新卡数须为 0–9999 的整数');
    }
    if (dailyReviewLimit < 0 || dailyReviewLimit > 99999) {
      throw ArgumentError('每日复习上限须为 0–99999 的整数');
    }
    if (desiredRetentionPercent < 70 || desiredRetentionPercent > 99) {
      throw ArgumentError('期望保持率须为 70–99 的整数百分比');
    }
  }

  final int dailyNewLimit;
  final int dailyReviewLimit;
  final int desiredRetentionPercent;
  double get desiredRetention => desiredRetentionPercent / 100;

  Map<String, Object> toJson() => {
    'dailyNewLimit': dailyNewLimit,
    'dailyReviewLimit': dailyReviewLimit,
    'desiredRetentionPercent': desiredRetentionPercent,
  };

  factory StudySettings.fromJson(Map<String, dynamic> json) {
    final fresh = json['dailyNewLimit'];
    final reviews = json['dailyReviewLimit'];
    final retention = json['desiredRetentionPercent'];
    if (fresh is! int || reviews is! int || retention is! int) {
      throw ArgumentError('学习设置格式无效');
    }
    return StudySettings(
      dailyNewLimit: fresh,
      dailyReviewLimit: reviews,
      desiredRetentionPercent: retention,
    );
  }
}
