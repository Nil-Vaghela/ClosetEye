import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../core/theme.dart';

/// Developer server-settings screen.
/// Access: Profile tab → long-press the version label (or ⚙ icon).
///
/// Allows switching between:
///  • LAN (home Wi-Fi)       http://10.x.x.x:8000
///  • ngrok tunnel           https://xxxx.ngrok-free.app
///  • Tailscale              http://100.x.x.x:8000
///  • Custom URL
///
/// The selected URL is persisted in SecureStorage and picked up by
/// AppConfig.baseUrl on every ApiClient call without requiring a rebuild.
class DevSettingsScreen extends StatefulWidget {
  const DevSettingsScreen({super.key});

  @override
  State<DevSettingsScreen> createState() => _DevSettingsScreenState();
}

class _DevSettingsScreenState extends State<DevSettingsScreen> {
  late TextEditingController _ctrl;
  _TestStatus _status = _TestStatus.idle;
  String _statusMsg = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: AppConfig.serverUrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _testConnection() async {
    final url = _ctrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return;

    setState(() {
      _status = _TestStatus.testing;
      _statusMsg = 'Connecting…';
    });

    try {
      final uri = Uri.parse('$url/api/v1/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode < 500) {
        setState(() {
          _status    = _TestStatus.ok;
          _statusMsg = '✓ Connected (HTTP ${res.statusCode})';
        });
      } else {
        setState(() {
          _status    = _TestStatus.err;
          _statusMsg = '✗ Server error ${res.statusCode}';
        });
      }
    } on Exception catch (e) {
      setState(() {
        _status    = _TestStatus.err;
        _statusMsg = '✗ ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _save() async {
    final url = _ctrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return;
    setState(() => _saving = true);
    await AppConfig.setServerUrl(url);
    if (mounted) {
      setState(() => _saving = false);
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Server URL saved — applies immediately'),
          backgroundColor: const Color(0xFF2D7D46),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _reset() async {
    await AppConfig.reset();
    setState(() {
      _ctrl.text  = AppConfig.serverUrl;
      _status     = _TestStatus.idle;
      _statusMsg  = '';
    });
    HapticFeedback.mediumImpact();
  }

  void _applyPreset(String hint) {
    HapticFeedback.selectionClick();
    setState(() {
      _ctrl.text = hint;
      _status    = _TestStatus.idle;
      _statusMsg = '';
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
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
                  const Text(
                    'Server Settings',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'DEV',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 1.5,
              decoration: BoxDecoration(
                gradient: AppColors.accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Active URL info ──────────────────────────────────────
                    _InfoCard(
                      label: 'Currently active',
                      value: AppConfig.serverUrl,
                      isCustom: AppConfig.isCustomUrl,
                    ),
                    const SizedBox(height: 24),

                    // ── Presets ──────────────────────────────────────────────
                    const _SectionLabel('QUICK PRESETS'),
                    const SizedBox(height: 10),
                    ...AppConfig.presets.map((p) => _PresetTile(
                          preset: p,
                          isActive: _ctrl.text.trim().startsWith(
                              p.hint.split('://').first + '://'),
                          onTap: () => _applyPreset(
                            p.label == 'LAN (home Wi-Fi)' ? p.hint : '',
                          ),
                          onLabelTap: () => _applyPreset(p.hint),
                        )),
                    const SizedBox(height: 24),

                    // ── URL input ────────────────────────────────────────────
                    const _SectionLabel('SERVER URL'),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          const Icon(Icons.link_rounded,
                              color: AppColors.textMuted, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: 'https://xxxx.ngrok-free.app',
                                hintStyle: TextStyle(
                                    color: AppColors.textHint, fontSize: 13),
                              ),
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              onChanged: (_) => setState(() {
                                _status    = _TestStatus.idle;
                                _statusMsg = '';
                              }),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              _ctrl.clear();
                              setState(() {
                                _status    = _TestStatus.idle;
                                _statusMsg = '';
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: const Icon(Icons.close_rounded,
                                  color: AppColors.textMuted, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Test button ──────────────────────────────────────────
                    GestureDetector(
                      onTap: _status == _TestStatus.testing
                          ? null
                          : _testConnection,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: AppColors.glassMid,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Center(
                          child: _status == _TestStatus.testing
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      color: AppColors.gold, strokeWidth: 2))
                              : const Text(
                                  'Test Connection',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    // ── Status chip ──────────────────────────────────────────
                    if (_statusMsg.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _status == _TestStatus.ok
                              ? const Color(0xFF2D7D46).withOpacity(0.1)
                              : _status == _TestStatus.err
                                  ? AppColors.error.withOpacity(0.1)
                                  : AppColors.glassMid,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _status == _TestStatus.ok
                                ? const Color(0xFF2D7D46).withOpacity(0.3)
                                : _status == _TestStatus.err
                                    ? AppColors.error.withOpacity(0.3)
                                    : AppColors.glassBorder,
                          ),
                        ),
                        child: Text(
                          _statusMsg,
                          style: TextStyle(
                            color: _status == _TestStatus.ok
                                ? const Color(0xFF2D7D46)
                                : _status == _TestStatus.err
                                    ? AppColors.error
                                    : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Save button ──────────────────────────────────────────
                    GestureDetector(
                      onTap: _saving ? null : _save,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: AppColors.accent,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withOpacity(0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _saving
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text(
                                  'Save & Apply',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    if (AppConfig.isCustomUrl) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _reset,
                        child: Container(
                          width: double.infinity,
                          padding:
                              const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.glassBorder),
                          ),
                          child: const Center(
                            child: Text(
                              'Reset to default LAN',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // ── How-to guide ─────────────────────────────────────────
                    const _SectionLabel('HOW TO TEST OUTSIDE HOME'),
                    const SizedBox(height: 12),
                    const _HowToCard(
                      icon: '🌐',
                      title: 'ngrok (easiest)',
                      steps: [
                        'brew install ngrok/ngrok/ngrok',
                        'ngrok config add-authtoken <token>  # free at ngrok.com',
                        'ngrok http 8000',
                        'Copy the https://xxxx.ngrok-free.app URL',
                        'Paste above → Save & Apply',
                      ],
                      note: 'Free tier URL changes on every restart.',
                    ),
                    const SizedBox(height: 10),
                    const _HowToCard(
                      icon: '🔒',
                      title: 'Tailscale (best — stable URL)',
                      steps: [
                        'Install Tailscale on Mac:  brew install tailscale',
                        'Install Tailscale app on your phone',
                        'Sign in to the same account on both',
                        'Mac Tailscale IP shows in menu bar (100.x.x.x)',
                        'Enter  http://100.x.x.x:8000  above',
                      ],
                      note: 'Free for personal use. URL never changes.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

enum _TestStatus { idle, testing, ok, err }

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
        ),
      );
}

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final bool isCustom;
  const _InfoCard(
      {required this.label, required this.value, required this.isCustom});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCustom
                ? AppColors.gold.withOpacity(0.35)
                : AppColors.glassBorder,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (isCustom)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('custom',
                    style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      );
}

class _PresetTile extends StatelessWidget {
  final dynamic preset;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLabelTap;

  const _PresetTile({
    required this.preset,
    required this.isActive,
    required this.onTap,
    required this.onLabelTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onLabelTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.gold.withOpacity(0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isActive ? AppColors.gold.withOpacity(0.4) : AppColors.glassBorder,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(preset.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preset.label,
                      style: TextStyle(
                        color: isActive
                            ? AppColors.gold
                            : AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )),
                  Text(preset.hint,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
            if (isActive)
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.gold, size: 18),
          ],
        ),
      ),
    );
  }
}

class _HowToCard extends StatefulWidget {
  final String icon;
  final String title;
  final List<String> steps;
  final String note;

  const _HowToCard({
    required this.icon,
    required this.title,
    required this.steps,
    required this.note,
  });

  @override
  State<_HowToCard> createState() => _HowToCardState();
}

class _HowToCardState extends State<_HowToCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  ...widget.steps.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              margin: const EdgeInsets.only(top: 1, right: 8),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${e.key + 1}',
                                  style: const TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                e.value,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  if (widget.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '💡 ${widget.note}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}
