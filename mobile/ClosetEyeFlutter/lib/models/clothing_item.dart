class ClothingItem {
  final String id;
  final String imageUrl;
  final String category;
  final String? color;
  final String? brand;
  final String? notes;
  final DateTime createdAt;

  const ClothingItem({
    required this.id,
    required this.imageUrl,
    required this.category,
    this.color,
    this.brand,
    this.notes,
    required this.createdAt,
  });

  factory ClothingItem.fromJson(Map<String, dynamic> j) => ClothingItem(
    id: j['id'] as String,
    imageUrl: j['image_url'] as String,
    category: j['category'] as String,
    color: j['color'] as String?,
    brand: j['brand'] as String?,
    notes: j['notes'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
  );

  static const categories = [
    'Tops', 'Bottoms', 'Dresses', 'Outerwear',
    'Shoes', 'Bags', 'Accessories', 'Other',
  ];
}
