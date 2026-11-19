import 'dart:convert';

class FontSettings {
  FontSettings({this.uiPercent = 100, this.cardPercent = 100}) {
    if (uiPercent < minUi ||
        uiPercent > maxUi ||
        cardPercent < minCard ||
        cardPercent > maxCard) {
      throw ArgumentError('字号比例超出可调范围');
    }
  }

  static const settingKey = 'fontSettings';
  static const minUi = 80;
  static const maxUi = 150;
  static const minCard = 80;
  static const maxCard = 200;
  final int uiPercent;
  final int cardPercent;

  Map<String, int> toJson() => {
    'uiPercent': uiPercent,
    'cardPercent': cardPercent,
  };

  /// Missing or invalid visual preferences must never block access to cards.
  factory FontSettings.decode(String? raw) {
    if (raw == null) return FontSettings();
    try {
      final json = jsonDecode(raw);
      if (json is! Map ||
          json['uiPercent'] is! int ||
          json['cardPercent'] is! int) {
        return FontSettings();
      }
      return FontSettings(
        uiPercent: json['uiPercent'] as int,
        cardPercent: json['cardPercent'] as int,
      );
    } on FormatException {
      return FontSettings();
    } on ArgumentError {
      return FontSettings();
    }
  }
}
