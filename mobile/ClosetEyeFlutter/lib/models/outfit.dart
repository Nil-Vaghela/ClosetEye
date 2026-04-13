class Outfit {
  final String id;
  final String? name;
  final List<String> itemIds;
  final String? previewUrl;
  final double? score;
  final DateTime createdAt;

  const Outfit({
    required this.id,
    this.name,
    required this.itemIds,
    this.previewUrl,
    this.score,
    required this.createdAt,
  });

  factory Outfit.fromJson(Map<String, dynamic> j) => Outfit(
    id: j['id'] as String,
    name: j['name'] as String?,
    itemIds: List<String>.from(j['item_ids'] as List? ?? []),
    previewUrl: j['preview_url'] as String?,
    score: (j['score'] as num?)?.toDouble(),
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}
