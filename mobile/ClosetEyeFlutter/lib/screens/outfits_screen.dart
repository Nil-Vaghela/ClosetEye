import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../widgets/blob_bg.dart';
import 'tryon_screen.dart';
import 'flatlay_preview_screen.dart';

class OutfitsScreen extends StatefulWidget {
  const OutfitsScreen({super.key});

  @override
  State<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends State<OutfitsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  int _selectedOccasion = 0;
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = false;      // true while calling GET (fetch saved)
  bool _generating = false;   // true while calling POST (AI generate)
  bool _hasLoaded = false;    // true once we got a response from GET
  bool _neverGenerated = true;
  bool _isStale = false;
  String? _error;

  static const _occasions = ['All', 'Casual', 'Work', 'Date Night', 'Formal'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Auto-load saved suggestions on open (instant, no AI call)
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchSaved());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// GET /suggestions/ — instant, returns saved suggestions from DB.
  Future<void> _fetchSaved() async {
    if (_loading || _generating) return;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiClient.getSuggestions();
      final raw = (data['outfits'] as List?) ?? [];
      setState(() {
        _suggestions = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _neverGenerated = data['never_generated'] as bool? ?? raw.isEmpty;
        _isStale = data['is_stale'] as bool? ?? false;
        _loading = false;
        _hasLoaded = true;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// POST /suggestions/generate — calls AI (~30-60s), saves to DB, returns fresh results.
  Future<void> _generateNew() async {
    if (_generating) return;
    setState(() { _generating = true; _error = null; });
    try {
      final occasion =
          _selectedOccasion > 0 ? _occasions[_selectedOccasion].toLowerCase() : null;
      final season = _getCurrentSeason();
      final data = await ApiClient.generateSuggestions(occasion: occasion, season: season);
      final raw = (data['outfits'] as List?) ?? [];
      setState(() {
        _suggestions = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _neverGenerated = false;
        _isStale = false;
        _generating = false;
        _hasLoaded = true;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _generating = false; });
    }
  }

  String _getCurrentSeason() {
    final m = DateTime.now().month;
    if (m >= 3 && m <= 5) return 'spring';
    if (m >= 6 && m <= 8) return 'summer';
    if (m >= 9 && m <= 11) return 'fall';
    return 'winter';
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      body: BlobBg(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildDivider(),
              _buildOccasionFilter(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.textPrimary, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Outfit Studio',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_hasLoaded && !_neverGenerated)
              GestureDetector(
                onTap: _generating ? null : _generateNew,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: AppColors.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _generating
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Refresh',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
          ],
        ),
      );

  Widget _buildDivider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: AppColors.accent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      );

  Widget _buildOccasionFilter() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
        child: SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _occasions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final sel = _selectedOccasion == i;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedOccasion = i);
                  if (_hasLoaded && !_neverGenerated) _generateNew();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    gradient: sel ? AppColors.accent : null,
                    color: sel ? null : AppColors.glassMid,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: sel ? Colors.transparent : AppColors.glassBorder,
                    ),
                  ),
                  child: Center(
                    child: Text(_occasions[i],
                        style: TextStyle(
                            color: sel
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontWeight: sel
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 12)),
                  ),
                ),
              );
            },
          ),
        ),
      );

  Widget _buildBody() {
    if (_loading) return _buildLoadingState(label: 'Loading your wardrobe…');
    if (_error != null) return _buildError();
    if (!_hasLoaded) return _buildLanding();       // no response yet (shouldn't happen)
    if (_neverGenerated) return _buildLanding();   // never run AI before
    if (_generating) return _buildLoadingState(label: 'Styling your wardrobe…');
    if (_suggestions.isEmpty) return _buildEmpty();
    return _buildSuggestionsList();
  }

  Widget _buildLanding() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: AppColors.accent,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.gold.withOpacity(0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8))
                  ],
                ),
                child: const Center(
                  child: Text('✨', style: TextStyle(fontSize: 40)),
                ),
              ),
              const SizedBox(height: 24),
              const Text('AI Outfit Studio',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Text(
                'Get AI-powered outfit combinations, mismatch warnings, and style tips from your wardrobe.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: _generateNew,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: AppColors.accent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.gold.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6))
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Generate Outfits',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildLoadingState({String label = 'Loading…'}) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AppColors.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              ),
            ),
            const SizedBox(height: 20),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Analysing colors, patterns & occasions',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😔', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _neverGenerated ? _generateNew : _fetchSaved,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  gradient: AppColors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Try Again',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            )
          ],
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👚', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('Add more clothes to get suggestions',
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _buildSuggestionsList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 110),
      itemCount: _suggestions.length + (_isStale ? 1 : 0),
      itemBuilder: (_, i) {
        // First item is stale banner if needed
        if (_isStale && i == 0) return _buildStaleBanner();
        final idx = _isStale ? i - 1 : i;
        return _OutfitCard(
          suggestion: _suggestions[idx],
          onTryOn: (itemIds) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TryOnScreen(preselectedIds: itemIds),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStaleBanner() => GestureDetector(
        onTap: _generating ? null : _generateNew,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.gold.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New clothes added!',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('Tap to refresh suggestions for your updated wardrobe',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              _generating
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: AppColors.gold, strokeWidth: 2))
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: AppColors.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Refresh',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Outfit Card
// ─────────────────────────────────────────────────────────────────────────────

class _OutfitCard extends StatefulWidget {
  final Map<String, dynamic> suggestion;
  final void Function(List<String> itemIds)? onTryOn;

  const _OutfitCard({required this.suggestion, this.onTryOn});

  @override
  State<_OutfitCard> createState() => _OutfitCardState();
}

class _OutfitCardState extends State<_OutfitCard> {
  bool _expanded = false;
  bool _generatingFlatlay = false;
  String? _flatlayUrl;

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    final name = s['name'] as String? ?? 'Outfit';
    final description = s['description'] as String? ?? '';
    final occasion = s['occasion'] as String? ?? 'casual';
    final styleNotes = s['style_notes'] as String? ?? '';
    final score = (s['compatibility_score'] as num? ?? 75).toInt();
    final warnings = List<String>.from(s['warnings'] as List? ?? []);
    final missingPiece = s['missing_piece'] as String?;
    final items = List<Map<String, dynamic>>.from(
        (s['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));

    final hasMismatch = warnings.isNotEmpty;
    final scoreColor = score >= 80
        ? const Color(0xFF4CAF50)
        : score >= 60
            ? AppColors.gold
            : const Color(0xFFE57373);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasMismatch
              ? const Color(0xFFE57373).withOpacity(0.4)
              : AppColors.glassBorder,
          width: hasMismatch ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(description,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Score ring
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        value: score / 100,
                        strokeWidth: 3.5,
                        backgroundColor:
                            AppColors.glassMid,
                        valueColor:
                            AlwaysStoppedAnimation(scoreColor),
                      ),
                    ),
                    Text('$score',
                        style: TextStyle(
                            color: scoreColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),

          // ── Garment image grid ───────────────────────────────────────
          if (items.isNotEmpty) _buildGarmentGrid(items),

          // ── Occasion + mismatch chips ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(
                  _occasionEmoji(occasion) + ' ' + _capitalize(occasion),
                  AppColors.gold.withOpacity(0.15),
                  AppColors.gold,
                ),
                ...warnings.map((w) => _chip(
                      '⚠️ $w',
                      const Color(0xFFE57373).withOpacity(0.12),
                      const Color(0xFFE57373),
                    )),
              ],
            ),
          ),

          // ── Style notes (expandable) ─────────────────────────────────
          if (styleNotes.isNotEmpty) ...[
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    const Text('💡 Style notes',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textMuted,
                        size: 18),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(styleNotes,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.5)),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],

          // ── Missing piece ────────────────────────────────────────────
          if (missingPiece != null && missingPiece.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.gold.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Text('🛍️',
                        style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Missing: $missingPiece',
                        style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Flatlay inline preview ───────────────────────────────────
          if (_flatlayUrl != null || _generatingFlatlay)
            _buildFlatlaySectionInline(),

          // ── Action buttons ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        label: 'Try On',
                        icon: Icons.checkroom_rounded,
                        outlined: true,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          final ids = items
                              .map((e) => e['id'] as String? ?? '')
                              .where((id) => id.isNotEmpty)
                              .toList();
                          widget.onTryOn?.call(ids);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionButton(
                        label: 'Save Look',
                        icon: Icons.bookmark_add_rounded,
                        outlined: false,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Outfit saved! ✨'),
                              backgroundColor: AppColors.gold,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // ── Flatlay button (full-width, secondary) ───────────
                _buildFlatLayButton(items),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGarmentGrid(List<Map<String, dynamic>> items) {
    // Show up to 4 items in a horizontal scroll row
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          final imageUrl = item['image_url'] as String?;
          final cat = item['category'] as String? ?? '';
          final itemName = item['name'] as String? ?? '';

          return Container(
            width: 82,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: AppColors.glassMid,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14)),
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            placeholder: (_, __) => Container(
                                color: AppColors.glassMid,
                                child: const Center(
                                    child: CircularProgressIndicator(
                                        color: AppColors.gold,
                                        strokeWidth: 1.5))),
                            errorWidget: (_, __, ___) => Container(
                                color: AppColors.glassMid,
                                child: const Center(
                                    child: Text('👕',
                                        style: TextStyle(fontSize: 24)))),
                          )
                        : Container(
                            color: AppColors.glassMid,
                            child: Center(
                                child: Text(_catEmoji(cat),
                                    style: const TextStyle(fontSize: 24))),
                          ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(4, 4, 4, 5),
                  child: Text(
                    itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String label, Color bg, Color text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: text,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool outlined,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: outlined ? null : AppColors.accent,
            color: outlined ? null : null,
            borderRadius: BorderRadius.circular(10),
            border: outlined
                ? Border.all(color: AppColors.gold)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: outlined ? AppColors.gold : Colors.white,
                  size: 14),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: outlined ? AppColors.gold : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  // ── Flatlay helpers ──────────────────────────────────────────────────────

  Widget _buildFlatLayButton(List<Map<String, dynamic>> items) {
    return GestureDetector(
      onTap: _generatingFlatlay
          ? null
          : () async {
              HapticFeedback.mediumImpact();
              final ids = items
                  .map((e) => e['id'] as String? ?? '')
                  .where((id) => id.isNotEmpty)
                  .toList();
              if (ids.isEmpty) return;

              if (_flatlayUrl != null) {
                // Already generated — open fullscreen preview
                if (!mounted) return;
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, a, __) =>
                        FlatLayPreviewScreen(imageUrl: fixUrl(_flatlayUrl!)),
                    transitionsBuilder: (_, a, __, child) => FadeTransition(
                      opacity: a, child: child,
                    ),
                  ),
                );
                return;
              }

              setState(() => _generatingFlatlay = true);
              try {
                final data = await ApiClient.generateFlatlay(itemIds: ids);
                final url = data['flatlay_url'] as String? ?? '';
                if (mounted) {
                  setState(() {
                    _flatlayUrl = url;
                    _generatingFlatlay = false;
                  });
                  HapticFeedback.heavyImpact();
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _generatingFlatlay = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Flatlay failed: $e'),
                      backgroundColor: Colors.red.shade700,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.glassMid,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_generatingFlatlay) ...[
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                    color: AppColors.gold, strokeWidth: 2),
              ),
              const SizedBox(width: 6),
              const Text('Generating Flatlay…',
                  style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ] else if (_flatlayUrl != null) ...[
              const Icon(Icons.photo_size_select_actual_rounded,
                  color: AppColors.gold, size: 14),
              const SizedBox(width: 5),
              const Text('View Flatlay',
                  style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ] else ...[
              const Text('🎨',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              const Text('Generate Flatlay',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFlatlaySectionInline() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _generatingFlatlay
            ? Container(
                height: 200,
                color: AppColors.glassMid,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
                      SizedBox(height: 12),
                      Text('Creating your outfit board…',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              )
            : _flatlayUrl != null
                ? GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, a, __) =>
                              FlatLayPreviewScreen(imageUrl: fixUrl(_flatlayUrl!)),
                          transitionsBuilder: (_, a, __, child) =>
                              FadeTransition(opacity: a, child: child),
                        ),
                      );
                    },
                    child: Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: fixUrl(_flatlayUrl!),
                          width: double.infinity,
                          height: 220,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            height: 220,
                            color: AppColors.glassMid,
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.gold, strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            height: 220,
                            color: AppColors.glassMid,
                            child: const Center(
                                child: Icon(Icons.broken_image_rounded,
                                    color: AppColors.textMuted)),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.open_in_full_rounded,
                                    color: Colors.white, size: 11),
                                SizedBox(width: 4),
                                Text('Full view',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
      ),
    );
  }

  String _occasionEmoji(String o) {
    switch (o.toLowerCase()) {
      case 'work':       return '💼';
      case 'date night': return '🌙';
      case 'formal':     return '🎩';
      case 'sport':      return '🏃';
      default:           return '☀️';
    }
  }

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

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
