import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../providers/auth_provider.dart';
import 'dev_settings_screen.dart';
import '../models/user.dart';
import 'wardrobe_screen.dart';
import 'login_screen.dart';
import 'body_model_screen.dart';
import 'outfits_screen.dart';
import 'tryon_screen.dart';
import 'shopping_screen.dart';
import 'ootd_screen.dart';
import 'capture_screen.dart';
import 'mix_match_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      body: IndexedStack(
        index: _tab,
        children: [
          const _HomeTab(),
          const WardrobeScreen(),
          const OutfitsScreen(),
          _ProfileTab(onSignOut: _signOut),
        ],
      ),
      bottomNavigationBar: _FloatingNav(
        index: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }

  Future<void> _signOut() async {
    await context.read<AppAuthProvider>().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }
}

// ── Nav ───────────────────────────────────────────────────────────────────────
class _NavItem {
  final IconData iconOff, iconOn;
  final String label;
  const _NavItem(this.iconOff, this.iconOn, this.label);
}

class _FloatingNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _FloatingNav({required this.index, required this.onTap});

  static const _items = [
    _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
    _NavItem(Icons.checkroom_outlined, Icons.checkroom_rounded, 'Wardrobe'),
    _NavItem(Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'Outfits'),
    _NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottom > 0 ? bottom + 4 : 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withOpacity(0.6)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 32, offset: const Offset(0, 8)),
                BoxShadow(color: AppColors.gold.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: List.generate(_items.length, (i) {
                final sel = i == index;
                final item = _items[i];
                return Expanded(
                  child: GestureDetector(
                    onTap: () { HapticFeedback.selectionClick(); onTap(i); },
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.gold.withOpacity(0.12) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(sel ? item.iconOn : item.iconOff, size: 22,
                              color: sel ? AppColors.gold : AppColors.textMuted),
                        ),
                        const SizedBox(height: 2),
                        Text(item.label, style: TextStyle(
                          fontSize: 10, letterSpacing: 0.3,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                          color: sel ? AppColors.gold : AppColors.textMuted,
                        )),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Home Tab ──────────────────────────────────────────────────────────────────
class _HomeTab extends StatefulWidget {
  const _HomeTab();
  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  int _itemCount = 0;
  int _outfitCount = 0;
  int _streak = 0;
  List<Map<String, dynamic>> _recentItems = [];
  Map<String, dynamic>? _todayLook;
  bool _loadingLook = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final results = await Future.wait([
        ApiClient.getWardrobe(),
        ApiClient.getOutfits(),
        ApiClient.getOOTDStreak(),
        ApiClient.getSuggestions(),
      ]);

      final wardrobe = results[0] as List;
      final outfits  = results[1] as List;
      final streak   = results[2] as Map<String, dynamic>;
      final sugg     = results[3] as Map<String, dynamic>;

      // Pick today's look: rotate through saved suggestions by day of week
      final outfitList = (sugg['outfits'] as List?) ?? [];
      Map<String, dynamic>? pick;
      if (outfitList.isNotEmpty) {
        final idx = DateTime.now().weekday % outfitList.length;
        pick = Map<String, dynamic>.from(outfitList[idx] as Map);
      }

      if (!mounted) return;
      setState(() {
        _itemCount   = wardrobe.length;
        _outfitCount = outfits.length;
        _streak      = (streak['current_streak'] as num? ?? 0).toInt();
        _recentItems = wardrobe
            .take(5)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _todayLook   = pick;
        _loadingLook = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLook = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user    = context.watch<AppAuthProvider>().user;
    final name    = user?.fullName?.split(' ').first ?? 'Stylist';
    final hasModel = user?.bodyModelReady == true;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [

        // ── Header ────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_greeting(), style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13, letterSpacing: 0.3)),
                      Text(name, style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 26,
                          fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1)),
                    ],
                  ),
                  const Spacer(),
                  // Date pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Text(_todayLabel(), style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () { HapticFeedback.lightImpact();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CaptureScreen())); },
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        gradient: AppColors.accent,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4))],
                      ),
                      child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── Stats row ─────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                Expanded(child: _StatCard(value: '$_itemCount', label: 'Items', icon: Icons.checkroom_rounded, color: const Color(0xFFDAA520))),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(value: '$_outfitCount', label: 'Saved Looks', icon: Icons.style_rounded, color: const Color(0xFF5B6EAE))),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(value: '$_streak', label: 'Day Streak', icon: Icons.local_fire_department_rounded,
                    color: _streak > 0 ? const Color(0xFFFF6B35) : AppColors.textMuted)),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // ── Mix & Match banner ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.push(context,
                    PageRouteBuilder(
                      pageBuilder: (_, a, __) => const MixMatchScreen(),
                      transitionsBuilder: (_, a, __, child) =>
                          SlideTransition(
                            position: Tween(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero)
                                .animate(CurvedAnimation(
                                    parent: a, curve: Curves.easeOutCubic)),
                            child: child,
                          ),
                      transitionDuration: const Duration(milliseconds: 350),
                    ));
              },
              child: Container(
                height: 76,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3D2B1F), Color(0xFF6B4226)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6B4226).withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Background emoji decoration
                    Positioned(
                      right: 14, top: 8,
                      child: Opacity(
                        opacity: 0.18,
                        child: const Text('👗👕👖🧥',
                            style: TextStyle(fontSize: 28, height: 1.3)),
                      ),
                    ),
                    // Content
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(Icons.style_rounded,
                                color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Mix & Match',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    )),
                                const SizedBox(height: 2),
                                Text('Drag items to build your outfit',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.65),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w400,
                                    )),
                              ],
                            ),
                          ),
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.arrow_forward_ios_rounded,
                                color: Colors.white, size: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 22)),

        // ── Today's Look ─────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: _loadingLook
                ? _TodayLookSkeleton()
                : _todayLook != null
                    ? _TodayLookCard(outfit: _todayLook!)
                    : _GenerateNudgeCard(),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 22)),

        // ── Avatar / Body Model ───────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: hasModel ? _BodyAvatarCard(user: user!) : _SetupAvatarCard(),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 22)),

        // ── Recent additions ──────────────────────────────────────────────
        if (_recentItems.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
              child: Row(
                children: [
                  const Text('Recent Additions', style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => HapticFeedback.selectionClick(),
                    child: const Text('See all', style: TextStyle(
                        color: AppColors.gold, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                itemCount: _recentItems.length,
                itemBuilder: (_, i) {
                  final item = _recentItems[i];
                  final url = (item['cleaned_image_url'] ?? item['original_image_url']) as String?;
                  final cat = (item['category'] as String? ?? '').toLowerCase();
                  return GestureDetector(
                    onTap: () { HapticFeedback.selectionClick();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const WardrobeScreen())); },
                    child: Container(
                      width: 85,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: url != null
                            ? CachedNetworkImage(imageUrl: fixUrl(url), fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Center(child: Text(_catEmoji(cat), style: const TextStyle(fontSize: 28))))
                            : Center(child: Text(_catEmoji(cat), style: const TextStyle(fontSize: 28))),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
        ],

        // ── Quick actions ─────────────────────────────────────────────────
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Text('QUICK ACTIONS', style: TextStyle(
                color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          sliver: SliverGrid(
            delegate: SliverChildListDelegate([
              _ActionTile(
                gradient: const LinearGradient(colors: [Color(0xFFB8860B), Color(0xFFDAA520)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                icon: Icons.auto_awesome_rounded, title: 'AI Stylist', sub: 'Generate outfits',
                onTap: () { HapticFeedback.lightImpact();
                  Navigator.push(context, _slide(const OutfitsScreen())); },
              ),
              _ActionTile(
                gradient: const LinearGradient(colors: [Color(0xFF2D3561), Color(0xFF5B6EAE)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                icon: Icons.accessibility_new_rounded, title: 'Try On', sub: 'Virtual fitting room',
                onTap: () { HapticFeedback.lightImpact();
                  Navigator.push(context, _slide(const TryOnScreen())); },
              ),
              _ActionTile(
                gradient: const LinearGradient(colors: [Color(0xFF1A5C3A), Color(0xFF2E9E6B)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                icon: Icons.shopping_bag_outlined, title: 'Shop Smart', sub: 'Fill wardrobe gaps',
                onTap: () { HapticFeedback.lightImpact();
                  Navigator.push(context, _slide(const ShoppingScreen())); },
              ),
              _ActionTile(
                gradient: const LinearGradient(colors: [Color(0xFF7B2D8B), Color(0xFFB06EBF)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                icon: Icons.calendar_today_rounded, title: 'Log OOTD', sub: 'Track your style',
                onTap: () { HapticFeedback.lightImpact();
                  Navigator.push(context, _slide(const OOTDScreen())); },
              ),
            ]),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.5),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  PageRouteBuilder _slide(Widget page) => PageRouteBuilder(
    pageBuilder: (_, a, __) => page,
    transitionsBuilder: (_, a, __, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 320),
  );
}

// ── Today's Look Card ─────────────────────────────────────────────────────────
class _TodayLookCard extends StatelessWidget {
  final Map<String, dynamic> outfit;
  const _TodayLookCard({required this.outfit});

  @override
  Widget build(BuildContext context) {
    final name    = outfit['name'] as String? ?? 'Today\'s Look';
    final occasion = outfit['occasion'] as String? ?? 'casual';
    final score   = (outfit['compatibility_score'] as num? ?? 80).toInt();
    final items   = List<Map<String, dynamic>>.from(
        (outfit['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final itemIds = items.map((e) => e['id'] as String? ?? '').where((s) => s.isNotEmpty).toList();

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF2D2B4E)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: const Color(0xFF2D2B4E).withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                  ),
                  child: const Text('✦ TODAY\'S LOOK', style: TextStyle(
                      color: AppColors.gold, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${_occasionEmoji(occasion)} ${_capitalize(occasion)}',
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: 14),

            // Garment images strip
            if (items.isNotEmpty)
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final url = items[i]['image_url'] as String?;
                    final cat = (items[i]['category'] as String? ?? '').toLowerCase();
                    return Container(
                      width: 72,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: url != null
                            ? CachedNetworkImage(imageUrl: fixUrl(url), fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Center(child: Text(_catEmoji(cat), style: const TextStyle(fontSize: 22))))
                            : Center(child: Text(_catEmoji(cat), style: const TextStyle(fontSize: 22))),
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 14),

            // Score + CTA row
            Row(
              children: [
                // Score
                Row(
                  children: [
                    SizedBox(
                      width: 32, height: 32,
                      child: CircularProgressIndicator(
                        value: score / 100,
                        strokeWidth: 3,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation(_scoreColor(score)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$score%', style: TextStyle(color: _scoreColor(score), fontSize: 13, fontWeight: FontWeight.w800)),
                        Text('Match', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                // Try On CTA
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => TryOnScreen(preselectedIds: itemIds)));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: AppColors.accent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.accessibility_new_rounded, color: Colors.white, size: 15),
                        SizedBox(width: 6),
                        Text('Try On Look', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(int s) => s >= 80 ? const Color(0xFF4CAF50) : s >= 60 ? AppColors.gold : const Color(0xFFE57373);
}

class _TodayLookSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 200,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.glassBorder),
    ),
    child: const Center(child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2)),
  );
}

class _GenerateNudgeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact();
      Navigator.push(context, MaterialPageRoute(builder: (_) => const OutfitsScreen())); },
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.gold.withOpacity(0.12), AppColors.gold.withOpacity(0.04)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Text('✨', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('No outfit for today yet', style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('Tap to let AI style you', style: TextStyle(
                    color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(gradient: AppColors.accent, borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]),
            child: const Text('Style me', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
}

// ── Body avatar card ──────────────────────────────────────────────────────────
class _BodyAvatarCard extends StatelessWidget {
  final AppUser user;
  const _BodyAvatarCard({required this.user});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact();
      Navigator.push(context, MaterialPageRoute(builder: (_) => const TryOnScreen())); },
    child: Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color(0xFF1A1A2E), Color(0xFF2D2B4E)]))),
            if (user.bodyPhotoUrl != null)
              CachedNetworkImage(imageUrl: user.bodyPhotoUrl!, fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorWidget: (_, __, ___) => _AvatarPlaceholder(user: user))
            else _AvatarPlaceholder(user: user),
            Positioned(bottom: 0, left: 0, right: 0, height: 90,
              child: Container(decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.75), Colors.transparent])))),
            Positioned(bottom: 16, left: 16, right: 16,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(5), border: Border.all(color: AppColors.gold.withOpacity(0.4))),
                    child: const Text('✦ MY AVATAR', style: TextStyle(color: AppColors.gold, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1.5))),
                  const SizedBox(height: 4),
                  Text(user.fullName ?? 'My Model', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  if (user.heightCm != null && user.weightKg != null)
                    Text('${user.heightCm} cm · ${user.weightKg} kg', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(gradient: AppColors.accent, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 3))]),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.accessibility_new_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 5),
                    Text('Try On', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ])),
              ])),
          ],
        ),
      ),
    ),
  );
}

class _AvatarPlaceholder extends StatelessWidget {
  final AppUser user;
  const _AvatarPlaceholder({required this.user});
  @override
  Widget build(BuildContext context) {
    final initials = (user.fullName ?? '?').split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A2E), Color(0xFF2D2B4E)])),
      child: Center(child: Container(
        width: 64, height: 64,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: AppColors.accent,
          boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.4), blurRadius: 20)]),
        child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
      )),
    );
  }
}

// ── Setup avatar card ─────────────────────────────────────────────────────────
class _SetupAvatarCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact();
      Navigator.push(context, MaterialPageRoute(builder: (_) => const BodyModelScreen())); },
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gold.withOpacity(0.35), width: 1.5),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.gold.withOpacity(0.08), AppColors.gold.withOpacity(0.02)]),
      ),
      child: Row(children: [
        Container(width: 64, height: 64,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [AppColors.gold.withOpacity(0.2), AppColors.gold.withOpacity(0.05)])),
          child: const Center(child: Text('🧍', style: TextStyle(fontSize: 32)))),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(5)),
            child: const Text('UNLOCK', style: TextStyle(color: AppColors.gold, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1.5))),
          const SizedBox(height: 6),
          const Text('Create your avatar', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 4),
          const Text('See clothes on you before buying', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
        ])),
        Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(gradient: AppColors.accent, borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3))]),
          child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18)),
      ]),
    ),
  );
}

// ── Stat card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _StatCard({required this.value, required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
    decoration: BoxDecoration(
      color: AppColors.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.glassBorder),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: Column(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(color: color == AppColors.textMuted ? AppColors.textPrimary : color,
          fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center, style: const TextStyle(
          color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w500)),
    ]),
  );
}

// ── Action tile ───────────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final Gradient gradient;
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  const _ActionTile({required this.gradient, required this.icon, required this.title, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: Colors.white, size: 20)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
        ]),
      ]),
    ),
  );
}

// ── Profile tab ───────────────────────────────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  final VoidCallback onSignOut;
  const _ProfileTab({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppAuthProvider>().user;
    final name = user?.fullName ?? 'Stylist';

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 120),
        child: Column(children: [
          // Avatar
          Container(width: 88, height: 88,
            decoration: BoxDecoration(gradient: AppColors.accent, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8))]),
            child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)))),
          const SizedBox(height: 14),
          Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          if (user?.phoneNumber != null) ...[
            const SizedBox(height: 4),
            Text(user!.phoneNumber, style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
          ],
          const SizedBox(height: 32),

          _SettingsRow(
            icon: Icons.accessibility_new_rounded, label: 'Body Model',
            trailing: _statusBadge(user?.bodyModelReady == true),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BodyModelScreen())),
          ),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.checkroom_rounded, label: 'My Wardrobe',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WardrobeScreen())),
          ),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.auto_awesome_rounded, label: 'Style DNA',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.dns_rounded,
            label: 'Server Settings',
            trailing: AppConfig.isCustomUrl
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('custom',
                        style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  )
                : null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const DevSettingsScreen()),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.logout_rounded, label: 'Sign Out',
            onTap: onSignOut, danger: true,
          ),
        ]),
      ),
    );
  }

  Widget _statusBadge(bool ready) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: (ready ? const Color(0xFF22C55E) : AppColors.gold).withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(ready ? 'Ready ✓' : 'Set up',
        style: TextStyle(color: ready ? const Color(0xFF22C55E) : AppColors.gold,
            fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool danger;
  const _SettingsRow({required this.icon, required this.label, required this.onTap, this.trailing, this.danger = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder)),
      child: Row(children: [
        Icon(icon, size: 20, color: danger ? AppColors.error : AppColors.textSecondary),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: TextStyle(
            color: danger ? AppColors.error : AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600))),
        trailing ?? Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
      ]),
    ),
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────
String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning,';
  if (h < 17) return 'Good afternoon,';
  return 'Good evening,';
}

String _todayLabel() {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final d = DateTime.now();
  return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
}

String _occasionEmoji(String o) {
  switch (o.toLowerCase()) {
    case 'work': return '💼'; case 'date night': return '🌙';
    case 'formal': return '🎩'; case 'sport': return '🏃';
    default: return '☀️';
  }
}

String _catEmoji(String cat) {
  switch (cat) {
    case 'top': return '👕'; case 'bottom': return '👖';
    case 'outerwear': return '🧥'; case 'shoes': return '👟';
    case 'dress': return '👗'; default: return '👚';
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String fixUrl(String url) => url
    .replaceFirst('http://localhost:8000', 'http://10.0.0.14:8000')
    .replaceFirst('https://localhost:8000', 'http://10.0.0.14:8000');
