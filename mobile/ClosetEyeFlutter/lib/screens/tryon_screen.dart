import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/theme.dart';
import '../models/clothing_item.dart';
import '../models/user.dart';
import '../widgets/gradient_button.dart';

class TryOnScreen extends StatefulWidget {
  final List<String> preselectedIds;
  const TryOnScreen({super.key, this.preselectedIds = const []});

  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen>
    with SingleTickerProviderStateMixin {

  List<ClothingItem> _wardrobe = [];
  Set<String> _selectedIds = {};
  bool _loading = false;
  bool _generating = false;
  String? _previewUrl;
  AppUser? _user;
  String _catFilter = 'All';

  late AnimationController _pulse;

  static const _cats = ['All', 'top', 'bottom', 'outerwear', 'shoes', 'dress'];
  static const _catEmojis = {'top': '👕', 'bottom': '👖', 'outerwear': '🧥', 'shoes': '👟', 'dress': '👗'};

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    if (widget.preselectedIds.isNotEmpty) {
      _selectedIds = Set<String>.from(widget.preselectedIds);
    }
    _loadData();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([ApiClient.getWardrobe(), ApiClient.getMe()]);
      if (!mounted) return;
      setState(() {
        _wardrobe = (results[0] as List).map((j) => ClothingItem.fromJson(j)).toList();
        _user = AppUser.fromJson(results[1] as Map<String, dynamic>);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e.toString());
    }
  }

  List<ClothingItem> get _filtered {
    if (_catFilter == 'All') return _wardrobe;
    return _wardrobe.where((i) => i.category.toLowerCase() == _catFilter.toLowerCase()).toList();
  }

  List<ClothingItem> get _selectedItems =>
      _wardrobe.where((i) => _selectedIds.contains(i.id)).toList();

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg.replaceAll('Exception: ', ''),
          style: const TextStyle(color: Colors.white)),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 5),
    ));
  }

  Future<void> _generatePreview() async {
    if (_selectedIds.isEmpty) {
      _showError('Select at least one item first.');
      return;
    }
    if (_user?.bodyModelReady != true) {
      _showError('Set up your body model in Profile → Body Model first.');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() { _generating = true; _previewUrl = null; });
    try {
      final response = await ApiClient.getTryOnPreview(itemIds: _selectedIds.toList());
      final rawUrl = response['preview_url'] as String?;
      if (!mounted) return;
      setState(() {
        _previewUrl = rawUrl != null ? fixUrl(rawUrl) : null;
        _generating = false;
      });
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      _showError(e.toString());
    }
  }

  Future<void> _saveOutfit(String name) async {
    try {
      await ApiClient.saveOutfit(
          name: name,
          itemIds: _selectedIds.toList(),
          previewUrl: _previewUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Outfit saved!'),
          backgroundColor: const Color(0xFF2D7D46),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showSaveDialog() {
    if (_previewUrl == null) return;
    String name = '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Save as Outfit',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: TextField(
          autofocus: true,
          onChanged: (v) => name = v,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Monday look',
            hintStyle: const TextStyle(color: AppColors.textHint),
            filled: true, fillColor: AppColors.bg,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.glassBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.gold)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () {
              if (name.isNotEmpty) { Navigator.pop(context); _saveOutfit(name); }
            },
            child: Text('Save',
                style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Container(
              margin: const EdgeInsets.fromLTRB(22, 0, 22, 0),
              height: 1.5,
              decoration: BoxDecoration(
                gradient: AppColors.accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2))
                  : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
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
            const SizedBox(width: 14),
            const Text('Virtual Try-On',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                )),
            const Spacer(),
            // Body model thumbnail
            if (_user?.bodySilhouetteUrl != null)
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.gold.withOpacity(0.4), width: 1.5),
                ),
                clipBehavior: Clip.hardEdge,
                child: CachedNetworkImage(
                  imageUrl: fixUrl(_user!.bodySilhouetteUrl!),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const Icon(
                      Icons.person_rounded, color: AppColors.textMuted, size: 20),
                ),
              )
            else if (_user != null && _user!.bodyModelReady != true)
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Icon(Icons.person_off_rounded,
                    color: Colors.orange, size: 18),
              ),
            if (_generating) ...[
              const SizedBox(width: 10),
              const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2)),
            ],
          ],
        ),
      );

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Body model warning ───────────────────────────────────────────
            if (_user?.bodyModelReady != true)
              _BodyModelBanner(),

            // ── Item selector ────────────────────────────────────────────────
            if (_wardrobe.isNotEmpty) ...[
              _sectionRow('SELECT ITEMS',
                  trailing: _selectedIds.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _selectedIds.clear());
                          },
                          child: const Text('Clear',
                              style: TextStyle(
                                  color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w600)),
                        )
                      : null),
              const SizedBox(height: 10),

              // Category filter chips
              _buildCategoryFilter(),
              const SizedBox(height: 10),

              // Item chips
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final item = _filtered[i];
                    return _ItemChip(
                      item: item,
                      selected: _selectedIds.contains(item.id),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (_selectedIds.contains(item.id)) {
                            _selectedIds.remove(item.id);
                          } else {
                            _selectedIds.add(item.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),

              // Selected items strip
              if (_selectedItems.isNotEmpty) ...[
                const SizedBox(height: 14),
                _SelectedStrip(items: _selectedItems),
              ],

              const SizedBox(height: 24),
            ] else ...[
              _EmptyWardrobe(),
              const SizedBox(height: 24),
            ],

            // ── Preview panel ────────────────────────────────────────────────
            _sectionRow('PREVIEW'),
            const SizedBox(height: 10),
            _PreviewPanel(
              generating: _generating,
              previewUrl: _previewUrl,
              selectedCount: _selectedIds.length,
              pulse: _pulse,
            ),
            const SizedBox(height: 18),

            // ── Buttons ──────────────────────────────────────────────────────
            GradientButton(
              label: _generating ? 'Generating…' : 'Generate Look',
              icon: _generating ? null : Icons.auto_fix_high_rounded,
              loading: _generating,
              onPressed: (_generating || _wardrobe.isEmpty) ? null : _generatePreview,
            ),

            // Regenerate (only after result) + Save
            if (_previewUrl != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _generating ? null : _generatePreview,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 16),
                          SizedBox(width: 6),
                          Text('Regenerate',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _showSaveDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.gold.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bookmark_add_outlined, color: AppColors.gold, size: 16),
                          const SizedBox(width: 6),
                          Text('Save Look',
                              style: TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),
            ],
          ],
        ),
      );

  // ── Category filter ─────────────────────────────────────────────────────────

  Widget _buildCategoryFilter() => SizedBox(
        height: 30,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _cats.length,
          itemBuilder: (_, i) {
            final cat = _cats[i];
            final sel = _catFilter == cat;
            final count = cat == 'All'
                ? _wardrobe.length
                : _wardrobe.where((w) => w.category.toLowerCase() == cat).length;
            if (count == 0 && cat != 'All') return const SizedBox.shrink();
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _catFilter = cat);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(right: 7),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  gradient: sel ? AppColors.accent : null,
                  color: sel ? null : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel ? Colors.transparent : AppColors.glassBorder,
                  ),
                ),
                child: Text(
                  cat == 'All' ? 'All  $count' : '${_catEmojis[cat] ?? ''} ${_capFirst(cat)}',
                  style: TextStyle(
                    color: sel ? Colors.white : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget _sectionRow(String label, {Widget? trailing}) => Row(
        children: [
          Text(label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.5,
              )),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      );

  String _capFirst(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// ── Body model warning banner ──────────────────────────────────────────────────

class _BodyModelBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withOpacity(0.25)),
        ),
        child: Row(children: [
          const Text('⚡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Body model not set up',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              SizedBox(height: 2),
              Text('Go to Profile → Body Model to enable photorealistic try-on.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.4)),
            ]),
          ),
        ]),
      );
}

// ── Selected items strip ───────────────────────────────────────────────────────

class _SelectedStrip extends StatelessWidget {
  final List<ClothingItem> items;
  const _SelectedStrip({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text('${items.length} selected',
                style: const TextStyle(
                    color: AppColors.gold, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                itemBuilder: (_, i) => Container(
                  width: 40, height: 40,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4EFE8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: CachedNetworkImage(
                    imageUrl: items[i].displayImageUrl,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.checkroom_rounded, color: AppColors.textMuted, size: 18),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Item chip ──────────────────────────────────────────────────────────────────

class _ItemChip extends StatelessWidget {
  final ClothingItem item;
  final bool selected;
  final VoidCallback onTap;
  const _ItemChip({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 86,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.glassBorder,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.gold.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))]
              : null,
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: item.displayImageUrl,
                fit: BoxFit.cover,
                width: 86, height: 112,
                placeholder: (_, __) => Container(color: AppColors.surface),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.surface,
                  child: const Center(child: Text('👕', style: TextStyle(fontSize: 24))),
                ),
              ),
            ),
            if (selected)
              Positioned(
                top: 6, right: 6,
                child: Container(
                  width: 20, height: 20,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.accent),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
                ),
              ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Text(
                  _capFirst(item.category),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capFirst(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// ── Preview panel ─────────────────────────────────────────────────────────────

class _PreviewPanel extends StatelessWidget {
  final bool generating;
  final String? previewUrl;
  final int selectedCount;
  final AnimationController pulse;

  const _PreviewPanel({
    required this.generating,
    required this.previewUrl,
    required this.selectedCount,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 420,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      clipBehavior: Clip.hardEdge,
      child: generating
          ? _GeneratingState(pulse: pulse)
          : previewUrl != null
              ? _ResultState(url: previewUrl!)
              : _IdleState(selectedCount: selectedCount),
    );
  }
}

class _GeneratingState extends StatelessWidget {
  final AnimationController pulse;
  const _GeneratingState({required this.pulse});

  static const _steps = [
    'Reading your body shape…',
    'Aligning garments…',
    'Adjusting fit and drape…',
    'Final render…',
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (_, __) => Transform.scale(
              scale: 0.9 + 0.1 * pulse.value,
              child: Container(
                width: 76, height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.accent,
                  boxShadow: [BoxShadow(
                    color: AppColors.goldDark.withOpacity(0.3 * pulse.value),
                    blurRadius: 24, spreadRadius: 4,
                  )],
                ),
                child: const Center(child: Text('✨', style: TextStyle(fontSize: 34))),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('AI is styling you…',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          // Animated step labels
          _AnimatedStepLabel(steps: _steps, pulse: pulse),
          const SizedBox(height: 6),
          const Text('Usually takes 20–45 seconds',
              style: TextStyle(color: AppColors.textHint, fontSize: 11)),
        ],
      ),
    );
  }
}

class _AnimatedStepLabel extends StatefulWidget {
  final List<String> steps;
  final AnimationController pulse;
  const _AnimatedStepLabel({required this.steps, required this.pulse});

  @override
  State<_AnimatedStepLabel> createState() => _AnimatedStepLabelState();
}

class _AnimatedStepLabelState extends State<_AnimatedStepLabel> {
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _advance();
  }

  Future<void> _advance() async {
    for (int i = 0; i < widget.steps.length; i++) {
      await Future.delayed(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _step = i);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: Text(
          widget.steps[_step],
          key: ValueKey(_step),
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      );
}

class _ResultState extends StatelessWidget {
  final String url;
  const _ResultState({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, a, __) => _FullScreenImage(url: url),
            transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: AppColors.surface),
            errorWidget: (_, __, ___) => const Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('👗', style: TextStyle(fontSize: 56)),
                SizedBox(height: 10),
                Text('Preview unavailable', style: TextStyle(color: AppColors.textMuted)),
              ]),
            ),
          ),
          Positioned(
            top: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.open_in_full_rounded, color: Colors.white, size: 11),
                SizedBox(width: 4),
                Text('Expand', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
          Positioned(
            bottom: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('✨', style: TextStyle(fontSize: 11)),
                SizedBox(width: 4),
                Text('IDM-VTON', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Full-screen viewer ────────────────────────────────────────────────────────

class _FullScreenImage extends StatelessWidget {
  final String url;
  const _FullScreenImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.8, maxScale: 5.0,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: url, fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2)),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0, right: 0,
              child: Center(
                child: Text('Tap to close  ·  Pinch to zoom',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Idle state ────────────────────────────────────────────────────────────────

class _IdleState extends StatelessWidget {
  final int selectedCount;
  const _IdleState({required this.selectedCount});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.glassMid,
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Center(child: Text('🪞', style: TextStyle(fontSize: 34))),
            ),
            const SizedBox(height: 16),
            Text(
              selectedCount == 0 ? 'Select clothes above' : '$selectedCount item${selectedCount > 1 ? 's' : ''} selected',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              selectedCount == 0 ? 'Tap items to build your outfit' : 'Press Generate Look below',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
}

// ── Empty wardrobe ────────────────────────────────────────────────────────────

class _EmptyWardrobe extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(children: [
          const Text('👗', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          const Text('Your wardrobe is empty',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Add clothes from the Wardrobe tab first.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              textAlign: TextAlign.center),
        ]),
      );
}
