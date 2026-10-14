enum ImportPhase { extracting, reading, media, saving }

class ImportProgress {
  const ImportProgress(this.phase, {this.completed = 0, this.total});
  final ImportPhase phase;
  final int completed;
  final int? total;

  String get label => switch (phase) {
    ImportPhase.extracting => '检查并解压牌组包',
    ImportPhase.reading => '读取卡片与安全处理内容',
    ImportPhase.media => '校验并暂存图片和音频',
    ImportPhase.saving => '保存到本地数据库',
  };
}
