import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../widgets/blob_bg.dart';
import '../widgets/glass_card.dart';
import '../providers/auth_provider.dart';
import 'wardrobe_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _tabs = [
    _Tab(Icons.home_outlined,          Icons.home_rounded,          'Home'),
    _Tab(Icons.checkroom_outlined,     Icons.checkroom_rounded,     'Wardrobe'),
    _Tab(Icons.auto_awesome_outlined,  Icons.auto_awesome_rounded,  'Outfits'),
    _Tab(Icons.person_outline_rounded, Icons.person_rounded,        'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    // Dark icons on light background
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true, // body flows behind floating pill
      body: BlobBg(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            _AppBar(tab: _tab),
            Expanded(
              child: IndexedStack(index: _tab, children: [
                const _HomeTab(),
                const WardrobeScreen(),
                const _ComingSoon('✨', 'AI Outfits',
                    'Smart outfit combinations coming soon'),
                _ProfileTab(onSignOut: _signOut),
              ]),
            ),
          ]),
        ),
      ),
      bottomNavigationBar: _FloatingPillNav(
        selectedIndex: _tab,
        tabs: _tabs,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }

  Future<void> _signOut() async {
    await context.read<AppAuthProvider>().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false);
  }
}

// ── Tab model ─────────────────────────────────────────────────────────────────
class _Tab {
  final IconData iconOff;
  final IconData iconOn;
  final String label;
  const _Tab(this.iconOff, this.iconOn, this.label);
}

// ── Floating pill navigation bar ──────────────────────────────────────────────
class _FloatingPillNav extends StatefulWidget {
  final int selectedIndex;
  final List<_Tab> tabs;
  final ValueChanged<int> onTap;

  const _FloatingPillNav({
    required this.selectedIndex,
    required this.tabs,
    required this.onTap,
  });

  @override
  State<_FloatingPillNav> createState() => _FloatingPillNavState();
}

class _FloatingPillNavState extends State<_FloatingPillNav> {
  @override
  void didUpdateWidget(_FloatingPillNav old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.fromLTRB(
        24, 8, 24, bottomPad > 0 ? bottomPad + 4 : 20,
      ),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.surface, // white pill
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            // Main depth shadow
            BoxShadow(
              color: Colors.black.withOpacity(0.09),
              blurRadius: 28,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
            // Warm gold ambient glow — very subtle
            BoxShadow(
              color: AppColors.gold.withOpacity(0.10),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: List.generate(widget.tabs.length, (i) {
            final selected = i == widget.selectedIndex;
            return Expanded(
              child: GestureDetector(
                onTap: () => widget.onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon — filled when active
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: Icon(
                        selected
                            ? widget.tabs[i].iconOn
                            : widget.tabs[i].iconOff,
                        key: ValueKey(selected),
                        size: 22,
                        color: selected
                            ? AppColors.gold
                            : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Label
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        letterSpacing: selected ? 0.4 : 0.2,
                        color: selected
                            ? AppColors.gold
                            : AppColors.textMuted,
                      ),
                      child: Text(widget.tabs[i].label),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ── App bar ───────────────────────────────────────────────────────────────────
class _AppBar extends StatelessWidget {
  final int tab;
  const _AppBar({required this.tab});

  static const _titles = ['Home', 'Wardrobe', 'Outfits', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppAuthProvider>().user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
      child: Row(children: [
        // Brand mark
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            gradient: AppColors.accent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.goldDark.withOpacity(0.18),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Text('👗', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _titles[tab],
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const Spacer(),
        if (tab == 0 && user != null)
          Text(
            'Hi, ${user.fullName?.split(' ').first ?? ''}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              letterSpacing: 0.3,
            ),
          ),
      ]),
    );
  }
}

// ── Home tab ──────────────────────────────────────────────────────────────────
class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppAuthProvider>().user;
    final name = user?.fullName?.split(' ').first ?? 'Stylist';

    return SingleChildScrollView(
      // Extra bottom padding so content clears the floating pill nav
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 110),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Welcome card ────────────────────────────────────────────────
        GlassCard(
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good ${_greeting()},',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    _Stat('0', 'Items'),
                    Container(
                      width: 1, height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      color: AppColors.glassBorder,
                    ),
                    _Stat('0', 'Outfits'),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Avatar
            Container(
              width: 56, height: 56,
              decoration: const BoxDecoration(
                gradient: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),

        // ── Section label ───────────────────────────────────────────────
        const Text(
          'QUICK ACTIONS',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.5,
          ),
        ),
        const SizedBox(height: 12),

        // ── Action grid ─────────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: _ActionCard(
              emoji: '📸',
              title: 'Add Clothes',
              sub: 'Snap & AI scans',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionCard(
              emoji: '✨',
              title: 'Get Outfit',
              sub: 'AI picks for today',
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _ActionCard(
              emoji: '🪞',
              title: 'Try On',
              sub: 'Virtual fitting room',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionCard(
              emoji: '🛍️',
              title: 'Shop Smart',
              sub: 'What to buy next',
            ),
          ),
        ]),

        const SizedBox(height: 24),

        // ── Tip ─────────────────────────────────────────────────────────
        GlassCard(
          child: Row(children: [
            Container(
              width: 2, height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Add your first item and let AI build your digital closet.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ],
      );
}

class _ActionCard extends StatelessWidget {
  final String emoji, title, sub;
  const _ActionCard({required this.emoji, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.glassBorder, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                letterSpacing: 0.2,
              ),
            ),
          ],
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
    final initial = user?.fullName?.isNotEmpty == true
        ? user!.fullName![0].toUpperCase()
        : '?';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 110),
      child: Column(children: [
        // Avatar
        Container(
          width: 88, height: 88,
          decoration: const BoxDecoration(
            gradient: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              initial,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 34,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          user?.fullName ?? '',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          user?.phoneNumber ?? '',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 30),

        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            _Row(icon: Icons.person_outline_rounded, label: 'Edit Profile', onTap: () {}),
            _HDivider(),
            _Row(icon: Icons.notifications_outlined, label: 'Notifications', onTap: () {}),
            _HDivider(),
            _Row(icon: Icons.help_outline_rounded, label: 'Help & Support', onTap: () {}),
            _HDivider(),
            _Row(
              icon: Icons.logout_rounded,
              label: 'Sign Out',
              color: AppColors.error,
              onTap: onSignOut,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _Row({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        dense: true,
        leading: Icon(icon, color: color ?? AppColors.textSecondary, size: 20),
        title: Text(label,
            style: TextStyle(
              color: color ?? AppColors.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            )),
        trailing: color == null
            ? const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 18)
            : null,
      );
}

class _HDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Divider(
      height: 1, color: AppColors.glassBorder, indent: 16, endIndent: 16);
}

// ── Coming soon ───────────────────────────────────────────────────────────────
class _ComingSoon extends StatelessWidget {
  final String emoji, title, sub;
  const _ComingSoon(this.emoji, this.title, this.sub);

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 8),
          Text(sub,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
        ]),
      );
}
