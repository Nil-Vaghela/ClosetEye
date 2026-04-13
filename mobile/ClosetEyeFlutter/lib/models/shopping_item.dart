class ShoppingItem {
  final String id;
  final String? name;
  final String category;
  final String? colorPrimary;
  final String originalImageUrl;
  final String? cleanedImageUrl;
  final DateTime expiresAt;
  final DateTime createdAt;

  const ShoppingItem({
    required this.id,
    this.name,
    required this.category,
    this.colorPrimary,
    required this.originalImageUrl,
    this.cleanedImageUrl,
    required this.expiresAt,
    required this.createdAt,
  });

  // Getter: display image URL — prefer cleaned, fall back to original
  String get displayImageUrl => cleanedImageUrl ?? originalImageUrl;

  factory ShoppingItem.fromJson(Map<String, dynamic> j) => ShoppingItem(
    id: j['id'] as String,
    name: j['name'] as String?,
    category: j['category'] as String,
    colorPrimary: j['color_primary'] as String?,
    originalImageUrl: j['original_image_url'] as String,
    cleanedImageUrl: j['cleaned_image_url'] as String?,
    expiresAt: DateTime.parse(j['expires_at'] as String),
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}
