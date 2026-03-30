class AppUser {
  final String id;
  final String phoneNumber;
  final String? fullName;
  final String? avatarUrl;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.phoneNumber,
    this.fullName,
    this.avatarUrl,
    required this.createdAt,
  });

  bool get isNewUser => fullName == null || fullName!.trim().isEmpty;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
    id: j['id'] as String,
    phoneNumber: j['phone_number'] as String,
    fullName: j['full_name'] as String?,
    avatarUrl: j['avatar_url'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'phone_number': phoneNumber,
    'full_name': fullName,
    'avatar_url': avatarUrl,
    'created_at': createdAt.toIso8601String(),
  };

  AppUser copyWith({String? fullName, String? avatarUrl}) => AppUser(
    id: id,
    phoneNumber: phoneNumber,
    fullName: fullName ?? this.fullName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    createdAt: createdAt,
  );
}
