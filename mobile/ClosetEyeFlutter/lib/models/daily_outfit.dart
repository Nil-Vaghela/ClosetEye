/// Models for the Daily Outfit Engine, Feedback, Memory System, and Notifications.
library;

// ─────────────────────────────────────────────────────────────────────────────
// DailyOutfit
// ─────────────────────────────────────────────────────────────────────────────

class DailyOutfit {
  final String? dailyOutfitId;
  final String date;
  final List<OutfitSuggestion> outfits;
  final bool cached;
  final WeatherInfo? weather;
  final String? message;

  const DailyOutfit({
    this.dailyOutfitId,
    required this.date,
    required this.outfits,
    required this.cached,
    this.weather,
    this.message,
  });

  factory DailyOutfit.fromJson(Map<String, dynamic> j) => DailyOutfit(
        dailyOutfitId: j['daily_outfit_id'] as String?,
        date: j['date'] as String? ?? '',
        outfits: (j['outfits'] as List<dynamic>? ?? [])
            .map((e) => OutfitSuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        cached: j['cached'] as bool? ?? false,
        weather: j['weather'] != null
            ? WeatherInfo.fromJson(j['weather'] as Map<String, dynamic>)
            : null,
        message: j['message'] as String?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// OutfitSuggestion
// ─────────────────────────────────────────────────────────────────────────────

class OutfitSuggestion {
  /// Map of category → clothing item UUID
  /// e.g. { "top": "abc-123", "bottom": "def-456", "shoes": "ghi-789" }
  final Map<String, String> items;
  final int confidenceScore;
  final ScoreBreakdown? breakdown;
  final String reason;

  const OutfitSuggestion({
    required this.items,
    required this.confidenceScore,
    this.breakdown,
    required this.reason,
  });

  factory OutfitSuggestion.fromJson(Map<String, dynamic> j) => OutfitSuggestion(
        items: Map<String, String>.from(j['items'] as Map? ?? {}),
        confidenceScore: (j['confidence_score'] as num?)?.toInt() ?? 0,
        breakdown: j['breakdown'] != null
            ? ScoreBreakdown.fromJson(j['breakdown'] as Map<String, dynamic>)
            : null,
        reason: j['reason'] as String? ?? '',
      );

  /// All item IDs as a flat list (for API calls)
  List<String> get allItemIds => items.values.toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// ScoreBreakdown
// ─────────────────────────────────────────────────────────────────────────────

class ScoreBreakdown {
  final int color;
  final int weather;
  final int occasion;
  final int style;

  const ScoreBreakdown({
    required this.color,
    required this.weather,
    required this.occasion,
    required this.style,
  });

  factory ScoreBreakdown.fromJson(Map<String, dynamic> j) => ScoreBreakdown(
        color:    (j['color']    as num?)?.toInt() ?? 0,
        weather:  (j['weather']  as num?)?.toInt() ?? 0,
        occasion: (j['occasion'] as num?)?.toInt() ?? 0,
        style:    (j['style']    as num?)?.toInt() ?? 0,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// WeatherInfo
// ─────────────────────────────────────────────────────────────────────────────

class WeatherInfo {
  final double? tempC;
  final String condition;
  final String description;

  const WeatherInfo({this.tempC, required this.condition, this.description = ''});

  factory WeatherInfo.fromJson(Map<String, dynamic> j) => WeatherInfo(
        tempC:       (j['temp_c'] as num?)?.toDouble(),
        condition:   j['condition'] as String? ?? 'unknown',
        description: j['description'] as String? ?? '',
      );

  String get icon {
    switch (condition) {
      case 'sunny':  return '☀️';
      case 'cloudy': return '⛅';
      case 'rainy':  return '🌧️';
      case 'snowy':  return '❄️';
      case 'stormy': return '⛈️';
      default:       return '🌤';
    }
  }

  String get tempDisplay => tempC != null ? '${tempC!.round()}°C' : '--';
}

// ─────────────────────────────────────────────────────────────────────────────
// AppNotification
// ─────────────────────────────────────────────────────────────────────────────

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final Map<String, dynamic> payload;
  final bool isRead;
  final DateTime? sentAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.payload,
    required this.isRead,
    this.sentAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id:      j['id'] as String,
        type:    j['type'] as String? ?? '',
        title:   j['title'] as String? ?? '',
        message: j['message'] as String? ?? '',
        payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? {},
        isRead:  j['is_read'] as bool? ?? false,
        sentAt:  j['sent_at'] != null ? DateTime.tryParse(j['sent_at'] as String) : null,
      );

  String get typeIcon {
    switch (type) {
      case 'morning_outfit':    return '✨';
      case 'weather_mismatch':  return '🌤';
      case 'unused_item':       return '👕';
      case 'repetition_warning': return '🔄';
      default:                  return '🔔';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OccasionMode
// ─────────────────────────────────────────────────────────────────────────────

enum OccasionMode {
  casual('casual', '👟', 'Casual'),
  gym('gym', '🏋️', 'Gym'),
  office('office', '💼', 'Office'),
  date('date', '💑', 'Date Night'),
  travel('travel', '✈️', 'Travel');

  const OccasionMode(this.value, this.emoji, this.label);
  final String value;
  final String emoji;
  final String label;
}
