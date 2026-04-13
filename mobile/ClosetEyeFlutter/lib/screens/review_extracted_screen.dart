import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/api_client.dart';
import '../core/theme.dart';

/// Data class for an extracted item returned by the backend.
class _ExtractedItem {
  final String name;
  final String category;
  final String? subcategory;
  final String? colorPrimary;
  final String? colorSecondary;
  final List<String> color;
  final String? description;
  final String season;
  final List<String> tags;
  final String? pattern;
  final String? material;
  final String? fit;
  final Map<String, dynamic> attributes;
  final double confidence;
  final String? productImageUrl;

  _ExtractedItem({
    required this.name,
    required this.category,
    this.subcategory,
    this.colorPrimary,
    this.colorSecondary,
    this.color = const [],
    this.description,
    required this.season,
    required this.tags,
    this.pattern,
    this.material,
    this.fit,
    this.attributes = const {},
    this.confidence = 1.0,
    this.productImageUrl,
  });

  factory _ExtractedItem.fromJson(Map<String, dynamic> j) {
    final colorList = j['color'] != null
        ? List<String>.from(j['color'] as List)
        : <String>[];
    return _ExtractedItem(
      name: j['name'] as String? ?? 'Item',
      category: j['category'] as String? ?? 'other',
      subcategory: j['subcategory'] as String?,
      colorPrimary: j['color_primary'] as String? ??
          (colorList.isNotEmpty ? colorList[0] : null),
      colorSecondary: j['color_secondary'] as String? ??
          (colorList.length > 1 ? colorList[1] : null),
      color: colorList,
      description: j['description'] as String?,
      season: j['season'] as String? ?? 'all',
      tags: List<String>.from(j['tags'] as List? ?? []),
      pattern: j['pattern'] as String?,
      material: j['material'] as String?,
      fit: j['fit'] as String?,
      attributes: Map<String, dynamic>.from(
          j['attributes'] as Map? ?? {}),
      confidence: (j['confidence'] as num?)?.toDouble() ?? 1.0,
      productImageUrl: j['product_image_url'] != null
          ? fixUrl(j['product_image_url'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'subcategory': subcategory,
        'color_primary': colorPrimary,
        'color_secondary': colorSecondary,
        'color': color,
        'season': season,
        'tags': tags,
        'pattern': pattern,
        'material': material,
        'fit': fit,
        'attributes': attributes,
        'confidence': confidence,
        'product_image_url': productImageUrl,
      };
}

class ReviewExtractedScreen extends StatefulWidget {
  final String originalImageUrl;
  final List<_ExtractedItem> items;

  const ReviewExtractedScreen({
    super.key,
    required this.originalImageUrl,
    required this.items,
  });

  /// Build from backend JSON response.
  factory ReviewExtractedScreen.fromResponse(Map<String, dynamic> response) {
    final rawItems = response['items'] as List;
    return ReviewExtractedScreen(
      originalImageUrl: fixUrl(response['original_image_url'] as String),
      items: rawItems.map((j) => _ExtractedItem.fromJson(j)).toList(),
    );
  }

  @override
  State<ReviewExtractedScreen> createState() => _ReviewExtractedScreenState();
}

class _ReviewExtractedScreenState extends State<ReviewExtractedScreen> {
  late Set<int> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Select all by default
    _selected = Set.from(List.generate(widget.items.length, (i) => i));
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == widget.items.length) {
        _selected.clear();
      } else {
        _selected = Set.from(List.generate(widget.items.length, (i) => i));
      }
    });
  }

  void _toggle(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
    });
  }

  Future<void> _addSelected() async {
    if (_selected.isEmpty) return;
    setState(() => _saving = true);

    try {
      final selectedItems = _selected
          .map((i) => widget.items[i].toJson())
          .toList();

      await ApiClient.batchAddItems(
        originalImageUrl: widget.originalImageUrl,
        items: selectedItems,
      );

      if (!mounted) return;
      // Pop all the way back to home
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${_selected.length} item${_selected.length > 1 ? 's' : ''} added to wardrobe',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2D7D46),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.textPrimary, size: 18),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Review Extracted Items',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              height: 1.5,
              decoration: BoxDecoration(
                gradient: AppColors.accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),

            // ── Scrollable body ─────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 100 + bottomPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Original photo
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: CachedNetworkImage(
                          imageUrl: widget.originalImageUrl,
                          height: 260,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            height: 260,
                            color: AppColors.surface,
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.gold, strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            height: 260,
                            color: AppColors.surface,
                            child: const Center(
                                child:
                                    Text('📷', style: TextStyle(fontSize: 48))),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // AI generated items + Select All
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.auto_awesome_rounded,
                              color: AppColors.gold, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            'AI detected items',
                            style: TextStyle(
                              color: AppColors.goldDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _toggleAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Text(
                            _selected.length == widget.items.length
                                ? 'Deselect All'
                                : 'Select All',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),

                    // Items grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: widget.items.length,
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        final selected = _selected.contains(index);
                        return _ItemCard(
                          item: item,
                          // Show DALL-E 3 HD product image when available,
                          // fall back to original outfit photo.
                          displayImageUrl: item.productImageUrl ?? widget.originalImageUrl,
                          selected: selected,
                          onTap: () => _toggle(index),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // ── Bottom action bar ─────────────────────────────────────────────────
      bottomSheet: Container(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottomPad),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border:
              const Border(top: BorderSide(color: AppColors.glassBorder)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: (_saving || _selected.isEmpty) ? null : _addSelected,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: (_saving || _selected.isEmpty)
                    ? null
                    : AppColors.accent,
                color: (_saving || _selected.isEmpty)
                    ? AppColors.glassBorder
                    : null,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _saving
                    ? [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 10),
                        const Text('Adding…',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                      ]
                    : [
                        const Icon(Icons.add_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _selected.isEmpty
                              ? 'Select items to add'
                              : 'Add ${_selected.length} to Wardrobe',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Text(
              'Discard',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Item card ───────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final _ExtractedItem item;
  final String displayImageUrl;
  final bool selected;
  final VoidCallback onTap;

  const _ItemCard({
    required this.item,
    required this.displayImageUrl,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: const Color(0xFFF0ECE4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? AppColors.gold
                      : AppColors.glassBorder,
                  width: selected ? 2.5 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.gold.withOpacity(0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Show the real original outfit photo
                    CachedNetworkImage(
                      imageUrl: displayImageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.gold, strokeWidth: 2),
                      ),
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          _categoryEmoji(item.category),
                          style: const TextStyle(fontSize: 40),
                        ),
                      ),
                    ),

                    // Category label pill overlay (bottom of card)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _categoryEmoji(item.category),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),

                    // AI sparkle badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: AppColors.gold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Center(
                          child: Icon(Icons.auto_fix_high_rounded,
                              color: AppColors.gold, size: 14),
                        ),
                      ),
                    ),

                    // Checkmark
                    if (selected)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.accent,
                          ),
                          child: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          // Item name
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          // Subcategory / material / fit chips
          if (item.subcategory != null ||
              item.material != null ||
              item.fit != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                [
                  if (item.subcategory != null) item.subcategory!,
                  if (item.material != null) item.material!,
                  if (item.fit != null) item.fit!,
                ].take(2).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          // Colour swatch row
          if (item.colorPrimary != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                _colorDot(item.colorPrimary!),
                if (item.colorSecondary != null) ...[
                  const SizedBox(width: 4),
                  _colorDot(item.colorSecondary!),
                ],
                const Spacer(),
                // Confidence badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${(item.confidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: AppColors.goldDark,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _colorDot(String hex) {
    Color? c;
    try {
      final h = hex.replaceAll('#', '');
      c = Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      c = Colors.grey;
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.black.withOpacity(0.12),
          width: 0.5,
        ),
      ),
    );
  }

  String _categoryEmoji(String cat) {
    switch (cat) {
      case 'top':
        return '👕';
      case 'bottom':
        return '👖';
      case 'dress':
        return '👗';
      case 'outerwear':
        return '🧥';
      case 'shoes':
        return '👟';
      case 'accessory':
        return '💍';
      default:
        return '👔';
    }
  }
}
