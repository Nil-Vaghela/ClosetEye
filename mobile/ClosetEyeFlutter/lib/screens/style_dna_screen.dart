import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../widgets/blob_bg.dart';

class StyleDnaScreen extends StatefulWidget {
  const StyleDnaScreen({super.key});

  @override
  State<StyleDnaScreen> createState() => _StyleDnaScreenState();
}

class _StyleDnaScreenState extends State<StyleDnaScreen>
    with SingleTickerProviderStateMixin {
  String? _dominantStyle;
  Map<String, double> _styleScores = {};
  String? _summary;
  List<String> _colors = [];
  Map<String, int> _categoryBreakdown = {};
  bool _loading = false;
  String? _error;

  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiClient.getStyleDna();
      setState(() {
        _dominantStyle = data['dominant_style'] as String?;
        _styleScores = Map<String, double>.from(
          (data['style_scores'] as Map?)?.cast<String, dynamic>().map(
                (k, v) => MapEntry(k, (v as num).toDouble()),
              ) ??
              {},
        );
        _summary = data['summary'] as String?;
        _loading = false;
      });

      // Animate scores
      _animCtrl.forward();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
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
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Your Style DNA',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: AppColors.accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.gold,
                          strokeWidth: 2,
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('😔',
                                    style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 16),
                                Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            padding:
                                const EdgeInsets.fromLTRB(22, 24, 22, 110),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Dominant style
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.gold.withOpacity(0.12),
                                        AppColors.goldMid.withOpacity(0.06),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color:
                                          AppColors.gold.withOpacity(0.22),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Text('✨',
                                          style: TextStyle(fontSize: 40)),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Your Style',
                                              style: TextStyle(
                                                color:
                                                    AppColors.textMuted,
                                                fontSize: 12,
                                                fontWeight:
                                                    FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _dominantStyle ?? 'Loading...',
                                              style: const TextStyle(
                                                color:
                                                    AppColors.textPrimary,
                                                fontSize: 24,
                                                fontWeight:
                                                    FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 32),
                                // Summary
                                if (_summary != null) ...[
                                  const Text(
                                    'ANALYSIS',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 2.5,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _summary!,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 14,
                                      height: 1.6,
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                ],
                                // Style breakdown
                                const Text(
                                  'STYLE BREAKDOWN',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ..._styleScores.entries.map((e) {
                                  final score = e.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment
                                                  .spaceBetween,
                                          children: [
                                            Text(
                                              e.key,
                                              style: const TextStyle(
                                                color:
                                                    AppColors.textPrimary,
                                                fontSize: 13,
                                                fontWeight:
                                                    FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              '${score.toStringAsFixed(0)}%',
                                              style: const TextStyle(
                                                color: AppColors.gold,
                                                fontSize: 12,
                                                fontWeight:
                                                    FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value:
                                                (score / 100)
                                                    .clamp(0, 1)
                                                    .toDouble(),
                                            minHeight: 8,
                                            backgroundColor:
                                                AppColors.glassMid,
                                            valueColor:
                                                const AlwaysStoppedAnimation(
                                              AppColors.gold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                const SizedBox(height: 32),
                                // Color palette
                                const Text(
                                  'YOUR PALETTE',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _getCommonColors().map((color) {
                                    return Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppColors.glassBorder,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _getCommonColors() {
    // Placeholder color palette based on common wardrobe colors
    return [
      const Color(0xFFFFFFFF),
      const Color(0xFF1C1A16),
      const Color(0xFFBEBBB3),
      const Color(0xFFC49B3C),
      const Color(0xFF8B4513),
      const Color(0xFFA9A9A9),
    ];
  }
}
