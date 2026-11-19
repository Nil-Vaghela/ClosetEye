import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../core/location.dart';
import '../models/daily_outfit.dart';
import '../models/clothing_item.dart';
import '../providers/wardrobe_provider.dart';
import 'package:provider/provider.dart';

/// Daily Outfit Engine screen — shows 1-3 AI-generated outfit suggestions
/// with confidence scores, occasion modes, weather info, and feedback loop.
class DailyOutfitScreen extends StatefulWidget {
  const DailyOutfitScreen({super.key});

  @override
  State<DailyOutfitScreen> createState() => _DailyOutfitScreenState();
}

class _DailyOutfitScreenState extends State<DailyOutfitScreen>
    with TickerProviderStateMixin {
  DailyOutfit? _data;
  bool _loading = false;
  String? _error;
  OccasionMode? _selectedOccasion;
  String? _dailyOutfitId;

  // Track which outfits have been liked/disliked (index → feedback)
  final Map<int, String> _feedbackGiven = {};
  int _currentOutfitIndex = 0;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final loc = await CoarseLocation.get();
      final raw = await ApiClient.getDailyOutfits(
        occasion: _selectedOccasion?.value,
        forceRefresh: forceRefresh,
        lat: loc?.lat,
        lon: loc?.lon,
      );
      final data = DailyOutfit.fromJson(raw);
      setState(() {
        _data = data;
        _dailyOutfitId = data.dailyOutfitId;
        _loading = false;
        _currentOutfitIndex = 0;
        _feedbackGiven.clear();
      });
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _submitFeedback(OutfitSuggestion outfit, int index, String feedback) async {
    setState(() => _feedbackGiven[index] = feedback);
    try {
      await ApiClient.submitOutfitFeedback(
        itemIds: outfit.allItemIds,
        feedback: feedback,
        dailyOutfitId: _dailyOutfitId,
      );
      if (feedback != 'like' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.textPrimary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(feedback == 'never_pair'
                ? "Got it. We won't pair these again."
                : "Got it. We'll learn your style.",
                style: TextStyle(color: Colors.white)),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _feedbackGiven.remove(index));
    }
  }

  Future<void> _logWorn(OutfitSuggestion outfit) async {
    try {
      await ApiClient.logOutfitWorn(
        itemIds: outfit.allItemIds,
        occasion: _selectedOccasion?.value,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Text("Logged! Nice look today 👗",
              style: TextStyle(color: Colors.white)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't log that outfit. $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildOccasionBar()),
          if (_loading)
            const SliverFillRemaining(child: _LoadingState())
          else if (_error != null)
            SliverFillRemaining(child: _ErrorState(error: _error!, onRetry: _load))
          else if (_data == null || _data!.outfits.isEmpty)
            const SliverFillRemaining(child: _EmptyState())
          else
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _buildContent(),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    final weather = _data?.weather;
    return SliverAppBar(
      expandedHeight: 100,
      floating: true,
      snap: true,
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        color: AppColors.textPrimary,
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Today\'s Picks',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5)),
                if (weather?.tempC != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${weather!.icon} ${weather.tempDisplay} · ${weather.condition}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ],
            ),
            _RefreshButton(onTap: () => _load(forceRefresh: true)),
          ],
        ),
        background: const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildOccasionBar() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _OccasionChip(
            label: 'All',
            emoji: '👗',
            selected: _selectedOccasion == null,
            onTap: () { setState(() => _selectedOccasion = null); _load(); },
          ),
          ...OccasionMode.values.map((m) => _OccasionChip(
            label: m.label,
            emoji: m.emoji,
            selected: _selectedOccasion == m,
            onTap: () { setState(() => _selectedOccasion = m); _load(); },
          )),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final outfits = _data!.outfits;
    return Column(
      children: [
        const SizedBox(height: 8),
        // Outfit cards
        ...outfits.asMap().entries.map((e) => _OutfitCard(
              outfit: e.value,
              index: e.key,
              isActive: _currentOutfitIndex == e.key,
              feedbackGiven: _feedbackGiven[e.key],
              onTap: () => setState(() => _currentOutfitIndex = e.key),
              onLike: () => _submitFeedback(e.value, e.key, 'like'),
              onDislike: () => _submitFeedback(e.value, e.key, 'dislike'),
              onNeverPair: () => _submitFeedback(e.value, e.key, 'never_pair'),
              onWornTap: () => _logWorn(e.value),
            )),
        const SizedBox(height: 8),
        if (_data!.cached)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'Outfits generated for ${_data!.date} · tap ↻ to refresh',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outfit Card
// ─────────────────────────────────────────────────────────────────────────────

class _OutfitCard extends StatelessWidget {
  final OutfitSuggestion outfit;
  final int index;
  final bool isActive;
  final String? feedbackGiven;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onDislike;
  final VoidCallback onNeverPair;
  final VoidCallback onWornTap;

  const _OutfitCard({
    required this.outfit,
    required this.index,
    required this.isActive,
    this.feedbackGiven,
    required this.onTap,
    required this.onLike,
    required this.onDislike,
    required this.onNeverPair,
    required this.onWornTap,
  });

  @override
  Widget build(BuildContext context) {
    final wardrobe = context.watch<WardrobeProvider>();
    final items = outfit.items.entries.map((e) {
      final item = wardrobe.items.firstWhere(
        (i) => i.id == e.value,
        orElse: () => ClothingItem.empty(id: e.value, category: e.key),
      );
      return MapEntry(e.key, item);
    }).toList();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive ? AppColors.gold : AppColors.glassBorder,
            width: isActive ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isActive ? 0.10 : 0.05),
              blurRadius: isActive ? 20 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header with outfit # and score
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Outfit ${index + 1}',
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8)),
                  _ConfidenceBadge(score: outfit.confidenceScore),
                ],
              ),
            ),

            // Item thumbnails grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _ItemGrid(items: items),
            ),

            // Score breakdown (shown when card is active)
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _ScoreBar(breakdown: outfit.breakdown),
              ),
              crossFadeState: isActive ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),

            // Reason text
            if (outfit.reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Text(
                  outfit.reason,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12, height: 1.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Action row: feedback + "I wore this"
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.glassBorder)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // 👍
                  _FeedbackButton(
                    icon: Icons.thumb_up_rounded,
                    label: 'Like',
                    active: feedbackGiven == 'like',
                    activeColor: AppColors.success,
                    onTap: feedbackGiven == null ? onLike : null,
                  ),
                  const SizedBox(width: 8),
                  // 👎
                  _FeedbackButton(
                    icon: Icons.thumb_down_rounded,
                    label: 'Nope',
                    active: feedbackGiven == 'dislike',
                    activeColor: AppColors.error,
                    onTap: feedbackGiven == null ? onDislike : null,
                  ),
                  const SizedBox(width: 8),
                  _FeedbackButton(
                    icon: Icons.block_rounded,
                    label: 'Never',
                    active: feedbackGiven == 'never_pair',
                    activeColor: AppColors.error,
                    onTap: feedbackGiven == null ? onNeverPair : null,
                  ),
                  const Spacer(),
                  // "I wore this"
                  GestureDetector(
                    onTap: onWornTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: AppColors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('I wore this',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Item Grid — shows top/bottom/shoes/jacket thumbnails
// ─────────────────────────────────────────────────────────────────────────────

class _ItemGrid extends StatelessWidget {
  final List<MapEntry<String, ClothingItem>> items;
  const _ItemGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((e) => _ItemTile(category: e.key, item: e.value)).toList(),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final String category;
  final ClothingItem item;
  const _ItemTile({required this.category, required this.item});

  @override
  Widget build(BuildContext context) {
    final size = _sizeForCategory(category);
    final url = fixUrl(item.displayImageUrl);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F1EC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => Center(
                child: Text(_catEmoji(category),
                    style: const TextStyle(fontSize: 22)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(_catLabel(category),
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 10, letterSpacing: 0.3)),
      ],
    );
  }

  double _sizeForCategory(String cat) {
    switch (cat) {
      case 'jacket':
      case 'top':
      case 'outerwear': return 80;
      case 'bottom':    return 80;
      case 'dress':     return 90;
      case 'shoes':     return 64;
      default:          return 72;
    }
  }

  String _catLabel(String cat) {
    const m = {
      'top': 'Top', 'bottom': 'Bottom', 'shoes': 'Shoes',
      'jacket': 'Jacket', 'outerwear': 'Jacket', 'dress': 'Dress',
    };
    return m[cat] ?? cat;
  }

  String _catEmoji(String cat) {
    const m = {
      'top': '👕', 'bottom': '👖', 'shoes': '👟',
      'jacket': '🧥', 'outerwear': '🧥', 'dress': '👗',
    };
    return m[cat] ?? '👔';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Confidence Badge — circular score indicator
// ─────────────────────────────────────────────────────────────────────────────

class _ConfidenceBadge extends StatelessWidget {
  final int score;
  const _ConfidenceBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 75
        ? AppColors.success
        : score >= 55
            ? AppColors.goldMid
            : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 11, color: color),
          const SizedBox(width: 4),
          Text('$score%',
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Score Bar — shows breakdown of color/weather/occasion/style
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreBar extends StatelessWidget {
  final ScoreBreakdown? breakdown;
  const _ScoreBar({this.breakdown});

  @override
  Widget build(BuildContext context) {
    if (breakdown == null) return const SizedBox.shrink();
    final bd = breakdown!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _BarRow(label: 'Color',   value: bd.color,   max: 25, icon: '🎨'),
          const SizedBox(height: 6),
          _BarRow(label: 'Weather', value: bd.weather,  max: 25, icon: '🌤'),
          const SizedBox(height: 6),
          _BarRow(label: 'Occasion', value: bd.occasion, max: 25, icon: '🎯'),
          const SizedBox(height: 6),
          _BarRow(label: 'Style',   value: bd.style,   max: 25, icon: '✨'),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final String icon;
  const _BarRow({required this.label, required this.value, required this.max, required this.icon});

  @override
  Widget build(BuildContext context) {
    final ratio = value / max;
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 6),
        SizedBox(
          width: 56,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: AppColors.glassBorder,
              valueColor: AlwaysStoppedAnimation(
                ratio >= 0.72 ? AppColors.success : AppColors.goldMid,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text('$value',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feedback Button
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _FeedbackButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.12) : AppColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? activeColor.withOpacity(0.4) : AppColors.glassBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? activeColor : AppColors.textMuted),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: active ? activeColor : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Occasion Chip
// ─────────────────────────────────────────────────────────────────────────────

class _OccasionChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  const _OccasionChip({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.accent : null,
          color: selected ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.glassBorder,
          ),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.gold.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
              : [],
        ),
        child: Text(
          '$emoji $label',
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Refresh Button
// ─────────────────────────────────────────────────────────────────────────────

class _RefreshButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RefreshButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: const Icon(Icons.refresh_rounded,
            size: 18, color: AppColors.textSecondary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// States
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2.5),
          SizedBox(height: 16),
          Text('Building your outfits...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('😕', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('👗', style: TextStyle(fontSize: 48)),
            SizedBox(height: 16),
            Text('No outfits yet',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text(
              'Add more items to your wardrobe to get personalized outfit suggestions.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
