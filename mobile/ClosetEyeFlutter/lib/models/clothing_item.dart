import '../core/api_client.dart';

class ClothingItem {
  final String id;
  final String? name;
  final String category;
  final String? colorPrimary;
  final String? colorSecondary;
  final String? brand;
  final String season;
  final List<String> tags;
  final String originalImageUrl;
  final String? cleanedImageUrl;
  final double? styleScore;
  final double? price;
  final int totalWears;
  final DateTime createdAt;

  const ClothingItem({
    required this.id,
    this.name,
    required this.category,
    this.colorPrimary,
    this.colorSecondary,
    this.brand,
    required this.season,
    required this.tags,
    required this.originalImageUrl,
    this.cleanedImageUrl,
    this.styleScore,
    this.price,
    required this.totalWears,
    required this.createdAt,
  });

  // Show the zone-cropped product image when available — it shows just the
  // garment area (shirt crop, trouser crop etc.) on a clean background.
  // Fall back to the original photo if no product image was generated.
  String get displayImageUrl => cleanedImageUrl ?? originalImageUrl;

  // Getter: category label mapping
  String get categoryLabel => categoryLabels[category] ?? category;

  factory ClothingItem.fromJson(Map<String, dynamic> j) {
    // Fix URLs that backend stored with 'localhost' — won't resolve on device
    String _fix(String url) => fixUrl(url);
    String? _fixN(String? url) => url == null ? null : fixUrl(url);

    return ClothingItem(
      id: j['id'] as String,
      name: j['name'] as String?,
      category: j['category'] as String,
      colorPrimary: j['color_primary'] as String?,
      colorSecondary: j['color_secondary'] as String?,
      brand: j['brand'] as String?,
      season: j['season'] as String? ?? 'all',
      tags: List<String>.from(j['tags'] as List? ?? []),
      originalImageUrl: _fix(j['original_image_url'] as String),
      cleanedImageUrl: _fixN(j['cleaned_image_url'] as String?),
      styleScore: (j['style_score'] as num?)?.toDouble(),
      price: (j['price'] as num?)?.toDouble(),
      totalWears: j['total_wears'] as int? ?? 0,
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }

  static const categories = ['top', 'bottom', 'dress', 'outerwear', 'shoes', 'accessory', 'other'];

  static const categoryLabels = {
    'top': 'Tops',
    'bottom': 'Bottoms',
    'dress': 'Dresses',
    'outerwear': 'Outerwear',
    'shoes': 'Shoes',
    'accessory': 'Accessories',
    'other': 'Other',
  };
}
