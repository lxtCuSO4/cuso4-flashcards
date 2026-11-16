/// Global defaults applied independently to each card's owning deck.
class StudySettings {
  StudySettings({
    this.dailyNewLimit = 20,
    this.dailyReviewLimit = 200,
    this.desiredRetentionPercent = 90,
    this.schedulingMode = 'fsrs',
    this.againMinutes = 10,
    this.hardDays = 1,
    this.goodDays = 3,
    this.easyDays = 7,
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
    if (schedulingMode != 'fsrs' && schedulingMode != 'calendar') {
      throw ArgumentError('未知的排程策略');
    }
    if (againMinutes < 1 || againMinutes > 1440) {
      throw ArgumentError('重来间隔须为 1–1440 分钟');
    }
    if (hardDays < 1 ||
        hardDays >= goodDays ||
        goodDays >= easyDays ||
        easyDays > 3650) {
      throw ArgumentError('困难、良好、简单须为递增的 1–3650 天整数');
    }
  }

  final int dailyNewLimit;
  final int dailyReviewLimit;
  final int desiredRetentionPercent;
  final String schedulingMode;
  final int againMinutes;
  final int hardDays;
  final int goodDays;
  final int easyDays;
  double get desiredRetention => desiredRetentionPercent / 100;

  Map<String, Object> toJson() => {
    'dailyNewLimit': dailyNewLimit,
    'dailyReviewLimit': dailyReviewLimit,
    'desiredRetentionPercent': desiredRetentionPercent,
    'schedulingMode': schedulingMode,
    'againMinutes': againMinutes,
    'hardDays': hardDays,
    'goodDays': goodDays,
    'easyDays': easyDays,
  };

  factory StudySettings.fromJson(Map<String, dynamic> json) {
    final fresh = json['dailyNewLimit'];
    final reviews = json['dailyReviewLimit'];
    final retention = json['desiredRetentionPercent'];
    if (fresh is! int || reviews is! int || retention is! int) {
      throw ArgumentError('学习设置格式无效');
    }
    int integer(String key, int fallback) {
      if (!json.containsKey(key)) return fallback;
      final value = json[key];
      if (value is! int) throw ArgumentError('学习设置格式无效：$key');
      return value;
    }

    final mode = json.containsKey('schedulingMode')
        ? json['schedulingMode']
        : 'fsrs';
    if (mode is! String) throw ArgumentError('排程策略格式无效');
    return StudySettings(
      dailyNewLimit: fresh,
      dailyReviewLimit: reviews,
      desiredRetentionPercent: retention,
      schedulingMode: mode,
      againMinutes: integer('againMinutes', 10),
      hardDays: integer('hardDays', 1),
      goodDays: integer('goodDays', 3),
      easyDays: integer('easyDays', 7),
    );
  }
}
