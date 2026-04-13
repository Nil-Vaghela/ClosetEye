import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/clothing_item.dart';
import 'tryon_screen.dart' as tryon_screen;

/// Mix & Match — instant drag-and-drop outfit builder.
///
/// Left panel  — scrollable wardrobe thumbnails with category filter.
/// Right panel — outfit board (local render, zero latency) + drop slots.
class MixMatchScreen extends StatefulWidget {
  const MixMatchScreen({super.key});

  @override
  State<MixMatchScreen> createState() => _MixMatchScreenState();
}

class _MixMatchScreenState extends State<MixMatchScreen> {
  List<ClothingItem> _wardrobe = [];
  bool _loading = true;
  String _filter = 'All';

  ClothingItem? _top;
  ClothingItem? _outerwear;
  ClothingItem? _bottom;
  ClothingItem? _shoes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.getWardrobe();
      setState(() {
        _wardrobe = (data as List)
            .map((j) => ClothingItem.fromJson(j as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<ClothingItem> get _filtered {
    if (_filter == 'All') return _wardrobe;
    return _wardrobe
        .where((i) => i.category.toLowerCase() == _filter.toLowerCase())
        .toList();
  }

  String _slotFor(String cat) {
    switch (cat.toLowerCase()) {
      case 'outerwear': return 'outerwear';
      case 'bottom':    return 'bottom';
      case 'shoes':     return 'shoes';
      default:          return 'top';
    }
  }

  void _place(ClothingItem item, {String? slot}) {
    HapticFeedback.mediumImpact();
    setState(() {
      switch (slot ?? _slotFor(item.category)) {
        case 'top':       _top       = item; break;
        case 'outerwear': _outerwear = item; break;
        case 'bottom':    _bottom    = item; break;
        case 'shoes':     _shoes     = item; break;
      }
    });
  }

  void _clear(String slot) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (slot) {
        case 'top':       _top       = null; break;
        case 'outerwear': _outerwear = null; break;
        case 'bottom':    _bottom    = null; break;
        case 'shoes':     _shoes     = null; break;
      }
    });
  }

  List<String> get _slottedIds => [
        _top?.id, _outerwear?.id, _bottom?.id, _shoes?.id,
      ].whereType<String>().toList();

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.gold, strokeWidth: 2))
                  : _body(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.textPrimary, size: 18),
              ),
            ),
            const SizedBox(width: 12),
            const Text('Mix & Match',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_slottedIds.isNotEmpty)
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _top = _outerwear = _bottom = _shoes = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.glassMid,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: const Text('Clear',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      );

  Widget _body() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Column(
              children: [
                _filterBar(),
                Expanded(child: _wardrobeList()),
              ],
            ),
          ),
          Container(width: 1, color: AppColors.glassBorder),
          Expanded(child: _outfitPanel()),
        ],
      );

  // ── Category filter ────────────────────────────────────────────────────────

  Widget _filterBar() {
    const cats   = ['All', 'top', 'outerwear', 'bottom', 'shoes'];
    const emojis = ['✦',   '👕',  '🧥',        '👖',     '👟'];
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        itemCount: cats.length,
        itemBuilder: (_, i) {
          final sel = _filter == cats[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _filter = cats[i]);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.fromLTRB(2, 5, 2, 4),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                gradient: sel ? AppColors.accent : null,
                color: sel ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(emojis[i],
                    style: TextStyle(
                      fontSize: cats[i] == 'All' ? 10 : 13,
                      color: sel ? Colors.white : AppColors.textMuted,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    )),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Wardrobe panel ─────────────────────────────────────────────────────────

  Widget _wardrobeList() {
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(10),
          child: Text('Empty',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(5, 4, 5, 120),
      itemCount: items.length,
      itemBuilder: (_, i) => _DraggableTile(
        item: items[i],
        onTap: () => _place(items[i]),
      ),
    );
  }

  // ── Right outfit panel ─────────────────────────────────────────────────────

  Widget _outfitPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _outfitBoard(),
          const SizedBox(height: 12),
          _slot('outerwear', '🧥', 'Jacket',      _outerwear),
          _slot('top',       '👕', 'Top / Dress',  _top),
          _slot('bottom',    '👖', 'Bottom',       _bottom),
          _slot('shoes',     '👟', 'Shoes',        _shoes),
          const SizedBox(height: 14),
          if (_slottedIds.isNotEmpty)
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => tryon_screen.TryOnScreen(
                        preselectedIds: _slottedIds),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  gradient: AppColors.accent,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.checkroom_rounded,
                        color: Colors.white, size: 16),
                    SizedBox(width: 7),
                    Text('Try On This Look',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Outfit board ───────────────────────────────────────────────────────────

  Widget _outfitBoard() {
    final empty = _slottedIds.isEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        // White board — feels like a real flatlay surface
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: empty
              ? AppColors.glassBorder
              : AppColors.gold.withOpacity(0.30),
          width: empty ? 1 : 1.5,
        ),
        boxShadow: empty
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      clipBehavior: Clip.hardEdge,
      child: empty ? _emptyHint() : _boardContent(),
    );
  }

  Widget _emptyHint() => SizedBox(
        height: 170,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('👗', style: TextStyle(fontSize: 42)),
            const SizedBox(height: 10),
            Text(
              'Tap or drag items to build\nyour outfit',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.grey[400], fontSize: 12.5, height: 1.5),
            ),
          ],
        ),
      );

  Widget _boardContent() {
    // Arrange items in a flatlay layout:
    //   Row: [jacket] [top]   ← side by side at top
    //        [bottom]         ← full width middle
    //        [shoes]          ← centered at bottom

    final topRow    = _outerwear != null || _top != null;
    final hasBottom = _bottom != null;
    final hasShoes  = _shoes != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── "OUTFIT BOARD" chip ──
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.10),
                borderRadius: BorderRadius.circular(7),
                border:
                    Border.all(color: AppColors.gold.withOpacity(0.22)),
              ),
              child: const Text(
                '✦  OUTFIT BOARD',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Jacket + Top row ──
          if (topRow)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_outerwear != null)
                    Expanded(
                      child: _boardPiece(
                        _outerwear!,
                        height: 148,
                      ),
                    ),
                  if (_outerwear != null && _top != null)
                    const SizedBox(width: 10),
                  if (_top != null)
                    Expanded(
                      child: _boardPiece(
                        _top!,
                        height: 148,
                      ),
                    ),
                ],
              ),
            ),

          if (topRow && (hasBottom || hasShoes))
            const SizedBox(height: 10),

          // ── Bottom ──
          if (hasBottom)
            _boardPiece(_bottom!, height: 118),

          if (hasBottom && hasShoes) const SizedBox(height: 10),

          // ── Shoes (centered, narrower) ──
          if (hasShoes)
            Center(
              child: SizedBox(
                width: 170,
                child: _boardPiece(_shoes!, height: 90),
              ),
            ),
        ],
      ),
    );
  }

  /// Single garment tile on the board — white/cream background, clean shadow.
  Widget _boardPiece(ClothingItem item, {required double height}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(item.id),
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F1EC),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: CachedNetworkImage(
          imageUrl: item.displayImageUrl,
          fit: BoxFit.contain,
          placeholder: (_, __) => Center(
            child: Text(
              _catEmoji(item.category),
              style: const TextStyle(fontSize: 30),
            ),
          ),
          errorWidget: (_, __, ___) => Center(
            child: Text(
              _catEmoji(item.category),
              style: const TextStyle(fontSize: 30),
            ),
          ),
        ),
      ),
    );
  }

  // ── Drop slot ──────────────────────────────────────────────────────────────

  Widget _slot(String key, String emoji, String label, ClothingItem? item) {
    return DragTarget<ClothingItem>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _place(d.data, slot: key),
      builder: (ctx, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: hovering
                ? AppColors.gold.withOpacity(0.06)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering
                  ? AppColors.gold
                  : item != null
                      ? AppColors.gold.withOpacity(0.30)
                      : AppColors.glassBorder,
              width: (hovering || item != null) ? 1.5 : 1,
            ),
          ),
          child: item == null
              ? _EmptySlot(emoji: emoji, label: label, hovering: hovering)
              : _FilledSlot(
                  item: item,
                  label: label,
                  onRemove: () => _clear(key),
                ),
        );
      },
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

String _catEmoji(String cat) {
  switch (cat.toLowerCase()) {
    case 'top':       return '👕';
    case 'bottom':    return '👖';
    case 'outerwear': return '🧥';
    case 'shoes':     return '👟';
    case 'dress':     return '👗';
    default:          return '👚';
  }
}

// ── Draggable wardrobe tile ────────────────────────────────────────────────────

class _DraggableTile extends StatelessWidget {
  final ClothingItem item;
  final VoidCallback onTap;
  const _DraggableTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Draggable<ClothingItem>(
      data: item,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(0.40),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CachedNetworkImage(
              imageUrl: item.displayImageUrl,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: _thumb()),
      onDragStarted: () => HapticFeedback.selectionClick(),
      child: GestureDetector(onTap: onTap, child: _thumb()),
    );
  }

  Widget _thumb() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 7),
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFFF0EBE3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: item.displayImageUrl,
              fit: BoxFit.contain,
              placeholder: (_, __) => Center(
                child: Text(_catEmoji(item.category),
                    style: const TextStyle(fontSize: 22)),
              ),
              errorWidget: (_, __, ___) => Center(
                child: Text(_catEmoji(item.category),
                    style: const TextStyle(fontSize: 22)),
              ),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.52),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  item.name ?? item.categoryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Slot widgets ───────────────────────────────────────────────────────────────

class _EmptySlot extends StatelessWidget {
  final String emoji, label;
  final bool hovering;
  const _EmptySlot(
      {required this.emoji, required this.label, required this.hovering});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                  color: hovering ? AppColors.gold : AppColors.textMuted,
                  fontSize: 13,
                  fontWeight:
                      hovering ? FontWeight.w600 : FontWeight.w500,
                )),
            const Spacer(),
            Text(
              hovering ? 'Drop here ↓' : '← drag or tap',
              style: TextStyle(
                color:
                    hovering ? AppColors.gold : AppColors.textHint,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
}

class _FilledSlot extends StatelessWidget {
  final ClothingItem item;
  final String label;
  final VoidCallback onRemove;
  const _FilledSlot(
      {required this.item, required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Draggable<ClothingItem>(
      data: item,
      feedback: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 56, height: 56,
            child: CachedNetworkImage(
                imageUrl: item.displayImageUrl, fit: BoxFit.cover),
          ),
        ),
      ),
      onDragStarted: () => HapticFeedback.mediumImpact(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 50, height: 50,
                child: CachedNetworkImage(
                  imageUrl: item.displayImageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: AppColors.glassMid),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 2),
                  Text(
                    item.name ?? item.categoryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                  if (item.colorPrimary != null)
                    Text(item.colorPrimary!,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 10)),
                ],
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: AppColors.glassMid,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close_rounded,
                    color: AppColors.textMuted, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
