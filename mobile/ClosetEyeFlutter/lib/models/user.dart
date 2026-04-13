import '../core/api_client.dart';

class AppUser {
  final String id;
  final String phoneNumber;
  final String? fullName;
  final String? avatarUrl;

  // Body model
  final String? bodyPhotoUrl;
  final String? bodySilhouetteUrl;
  final int? heightCm;
  final int? weightKg;
  final String? bodyType;
  final bool bodyModelReady;

  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.phoneNumber,
    this.fullName,
    this.avatarUrl,
    this.bodyPhotoUrl,
    this.bodySilhouetteUrl,
    this.heightCm,
    this.weightKg,
    this.bodyType,
    this.bodyModelReady = false,
    required this.createdAt,
  });

  bool get isNewUser => fullName == null || fullName!.trim().isEmpty;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        phoneNumber: j['phone_number'] as String,
        fullName: j['full_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        bodyPhotoUrl: _fixN(j['body_photo_url'] as String?),
        bodySilhouetteUrl: _fixN(j['body_silhouette_url'] as String?),
        heightCm: j['height_cm'] as int?,
        weightKg: j['weight_kg'] as int?,
        bodyType: j['body_type'] as String?,
        bodyModelReady: j['body_model_ready'] as bool? ?? false,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  static String? _fixN(String? url) => url == null ? null : fixUrl(url);

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone_number': phoneNumber,
        'full_name': fullName,
        'avatar_url': avatarUrl,
        'body_photo_url': bodyPhotoUrl,
        'body_silhouette_url': bodySilhouetteUrl,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'body_type': bodyType,
        'body_model_ready': bodyModelReady,
        'created_at': createdAt.toIso8601String(),
      };

  AppUser copyWith({
    String? fullName,
    String? avatarUrl,
    String? bodyPhotoUrl,
    String? bodySilhouetteUrl,
    int? heightCm,
    int? weightKg,
    String? bodyType,
    bool? bodyModelReady,
  }) =>
      AppUser(
        id: id,
        phoneNumber: phoneNumber,
        fullName: fullName ?? this.fullName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        bodyPhotoUrl: bodyPhotoUrl ?? this.bodyPhotoUrl,
        bodySilhouetteUrl: bodySilhouetteUrl ?? this.bodySilhouetteUrl,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        bodyType: bodyType ?? this.bodyType,
        bodyModelReady: bodyModelReady ?? this.bodyModelReady,
        createdAt: createdAt,
      );
}
