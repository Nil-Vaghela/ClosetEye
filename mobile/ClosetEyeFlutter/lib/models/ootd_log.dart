class OOTDLog {
  final String id;
  final String? outfitId;
  final List<String> itemIds;
  final String loggedDate; // "YYYY-MM-DD"
  final String? note;
  final DateTime createdAt;

  const OOTDLog({
    required this.id,
    this.outfitId,
    required this.itemIds,
    required this.loggedDate,
    this.note,
    required this.createdAt,
  });

  factory OOTDLog.fromJson(Map<String, dynamic> j) => OOTDLog(
    id: j['id'] as String,
    outfitId: j['outfit_id'] as String?,
    itemIds: List<String>.from(j['item_ids'] as List? ?? []),
    loggedDate: j['logged_date'] as String,
    note: j['note'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}
