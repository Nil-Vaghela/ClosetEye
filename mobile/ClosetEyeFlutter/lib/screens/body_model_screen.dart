import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/blob_bg.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import 'home_screen.dart';

// ── Body type options ─────────────────────────────────────────────────────────
class _BodyTypeOption {
  final String value;
  final String label;
  final String emoji;
  final String description;
  const _BodyTypeOption(this.value, this.label, this.emoji, this.description);
}

const _bodyTypes = [
  _BodyTypeOption('slim',     'Slim',     '🧍', 'Lean, narrow frame'),
  _BodyTypeOption('regular',  'Regular',  '🙂', 'Average build'),
  _BodyTypeOption('athletic', 'Athletic', '💪', 'Muscular, defined'),
  _BodyTypeOption('curvy',    'Curvy',    '✨', 'Fuller hips & bust'),
  _BodyTypeOption('plus',     'Plus',     '🌟', 'Plus size'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Body Model Screen — 4-step flow
// Step 0: Onboarding (why we need this)
// Step 1: Measurements (height, weight, body type)
// Step 2: Photo capture
// Step 3: Processing → Preview
// ─────────────────────────────────────────────────────────────────────────────

class BodyModelScreen extends StatefulWidget {
  /// Set to true when called from Profile settings (allows going back)
  final bool fromSettings;

  const BodyModelScreen({super.key, this.fromSettings = false});

  @override
  State<BodyModelScreen> createState() => _BodyModelScreenState();
}

class _BodyModelScreenState extends State<BodyModelScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pages = PageController();
  int _currentStep = 0;

  // Measurements
  int _heightCm = 170;
  int _weightKg = 65;
  String _bodyType = 'regular';

  // Photo
  File? _photo;

  // State
  bool _processing = false;
  bool _done = false;
  String? _error;
  String? _silhouetteUrl;

  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _pages.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
    setState(() => _currentStep++);
    _pages.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1200,
    );
    if (picked == null) return;
    setState(() => _photo = File(picked.path));
  }

  Future<void> _submit() async {
    if (_photo == null) return;
    setState(() { _processing = true; _error = null; });
    _nextStep(); // go to step 3 (processing/preview)

    try {
      await context.read<AppAuthProvider>().createBodyModel(
        photo: _photo!,
        heightCm: _heightCm,
        weightKg: _weightKg,
        bodyType: _bodyType,
      );
      final user = context.read<AppAuthProvider>().user;
      setState(() {
        _processing = false;
        _done = true;
        _silhouetteUrl = user?.bodySilhouetteUrl;
      });
      _fadeCtrl.reset();
      _fadeCtrl.forward();
    } catch (e) {
      setState(() {
        _processing = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _finish() {
    if (widget.fromSettings) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BlobBg(
        child: SafeArea(
          child: Column(children: [
            // ── Progress bar ─────────────────────────────────────────────
            _ProgressBar(step: _currentStep, total: 4),

            // ── Back button (settings) or close ──────────────────────────
            if (widget.fromSettings || _currentStep > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: GestureDetector(
                    onTap: () {
                      if (_currentStep > 0 && _currentStep < 3) {
                        setState(() => _currentStep--);
                        _pages.animateToPage(_currentStep,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOutCubic);
                      } else if (widget.fromSettings) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.glassBorder),
                        boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8, offset: const Offset(0, 2),
                        )],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColors.textPrimary, size: 16),
                    ),
                  ),
                ),
              ),

            // ── Page content ─────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _StepOnboarding(onNext: _nextStep),
                  _StepMeasurements(
                    heightCm: _heightCm,
                    weightKg: _weightKg,
                    bodyType: _bodyType,
                    onHeightChanged: (v) => setState(() => _heightCm = v),
                    onWeightChanged: (v) => setState(() => _weightKg = v),
                    onBodyTypeChanged: (v) => setState(() => _bodyType = v),
                    onNext: _nextStep,
                  ),
                  _StepPhoto(
                    photo: _photo,
                    onPickPhoto: _pickPhoto,
                    onSubmit: _submit,
                  ),
                  _StepPreview(
                    processing: _processing,
                    done: _done,
                    error: _error,
                    silhouetteUrl: _silhouetteUrl,
                    fade: _fade,
                    onRetry: () {
                      setState(() {
                        _currentStep = 2;
                        _error = null;
                        _processing = false;
                      });
                      _pages.animateToPage(2,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOutCubic);
                    },
                    onFinish: _finish,
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Progress bar ──────────────────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final int step, total;
  const _ProgressBar({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
      child: Row(
        children: List.generate(total, (i) {
          final active = i <= step;
          return Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: active ? AppColors.gold : AppColors.glassBorder,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Step 0: Onboarding ────────────────────────────────────────────────────────
class _StepOnboarding extends StatelessWidget {
  final VoidCallback onNext;
  const _StepOnboarding({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Illustration
        Center(
          child: Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              gradient: AppColors.accent,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: AppColors.goldDark.withOpacity(0.20),
                blurRadius: 24, offset: const Offset(0, 8),
              )],
            ),
            child: const Center(
              child: Text('🪞', style: TextStyle(fontSize: 54)),
            ),
          ),
        ),
        const SizedBox(height: 32),

        const Text(
          "Let's build\nyour body model",
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'We create a personal silhouette just for you — used to preview every outfit on YOUR body, not a generic mannequin.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 32),

        // Feature list
        _Feature('📏', 'Your measurements', 'Height, weight, body type — takes 10 seconds'),
        const SizedBox(height: 12),
        _Feature('📸', 'One reference photo', 'Stand straight, full body. We do the rest.'),
        const SizedBox(height: 12),
        _Feature('🤖', 'AI removes the background', 'Creates your clean silhouette instantly'),
        const SizedBox(height: 40),

        GradientButton(
          label: "Let's build my model",
          icon: Icons.arrow_forward_rounded,
          onPressed: onNext,
        ),

        const SizedBox(height: 16),
        Center(
          child: Text(
            'Your photo stays on your device and our server.\nWe never share or sell it.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ),
      ]),
    );
  }
}

class _Feature extends StatelessWidget {
  final String emoji, title, sub;
  const _Feature(this.emoji, this.title, this.sub);

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  )),
              const SizedBox(height: 2),
              Text(sub,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  )),
            ]),
          ),
        ]),
      );
}

// ── Step 1: Measurements ──────────────────────────────────────────────────────
class _StepMeasurements extends StatelessWidget {
  final int heightCm, weightKg;
  final String bodyType;
  final ValueChanged<int> onHeightChanged;
  final ValueChanged<int> onWeightChanged;
  final ValueChanged<String> onBodyTypeChanged;
  final VoidCallback onNext;

  const _StepMeasurements({
    required this.heightCm,
    required this.weightKg,
    required this.bodyType,
    required this.onHeightChanged,
    required this.onWeightChanged,
    required this.onBodyTypeChanged,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Your\nmeasurements',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Helps AI size garments correctly on your model',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 28),

        // Height
        _MeasurementSlider(
          label: 'Height',
          value: heightCm,
          unit: 'cm',
          min: 140,
          max: 220,
          onChanged: onHeightChanged,
        ),
        const SizedBox(height: 20),

        // Weight
        _MeasurementSlider(
          label: 'Weight',
          value: weightKg,
          unit: 'kg',
          min: 40,
          max: 200,
          onChanged: onWeightChanged,
        ),
        const SizedBox(height: 28),

        // Body type
        const Text(
          'BODY TYPE',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.5,
          ),
        ),
        const SizedBox(height: 12),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _bodyTypes.map((bt) {
            final selected = bodyType == bt.value;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onBodyTypeChanged(bt.value);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.gold.withOpacity(0.10) : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? AppColors.gold : AppColors.glassBorder,
                    width: selected ? 1.5 : 1.0,
                  ),
                  boxShadow: selected ? [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(0.12),
                      blurRadius: 8, offset: const Offset(0, 2),
                    ),
                  ] : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(bt.emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(
                    bt.label,
                    style: TextStyle(
                      color: selected ? AppColors.gold : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 13,
                    ),
                  ),
                ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 40),

        GradientButton(
          label: 'Next — Take photo',
          icon: Icons.camera_alt_outlined,
          onPressed: onNext,
        ),
      ]),
    );
  }
}

class _MeasurementSlider extends StatelessWidget {
  final String label, unit;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  const _MeasurementSlider({
    required this.label,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            RichText(
              text: TextSpan(children: [
                TextSpan(
                  text: '$value',
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ]),
            ),
          ]),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.gold,
              inactiveTrackColor: AppColors.glassBorder,
              thumbColor: AppColors.gold,
              overlayColor: AppColors.gold.withOpacity(0.12),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ]),
      );
}

// ── Step 2: Photo capture ─────────────────────────────────────────────────────
class _StepPhoto extends StatelessWidget {
  final File? photo;
  final Future<void> Function(ImageSource) onPickPhoto;
  final VoidCallback onSubmit;

  const _StepPhoto({
    required this.photo,
    required this.onPickPhoto,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Reference\nphoto',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Stand straight, full body visible, plain background if possible',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),

        // Photo preview / picker
        GestureDetector(
          onTap: () => _showSourcePicker(context),
          child: Container(
            height: 340,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: photo != null ? AppColors.gold : AppColors.glassBorder,
                width: photo != null ? 1.5 : 1.0,
              ),
              boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12, offset: const Offset(0, 4),
              )],
            ),
            clipBehavior: Clip.hardEdge,
            child: photo != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.file(photo!, fit: BoxFit.cover),
                    // Retake overlay
                    Positioned(
                      bottom: 12, right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 8,
                          )],
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.refresh_rounded, size: 14, color: AppColors.gold),
                          SizedBox(width: 6),
                          Text('Retake',
                              style: TextStyle(
                                color: AppColors.gold,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              )),
                        ]),
                      ),
                    ),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_outlined,
                          color: AppColors.gold, size: 32),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tap to add photo',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Camera or gallery',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ]),
          ),
        ),

        const SizedBox(height: 14),

        // Photo guide
        _PhotoGuide(),

        const SizedBox(height: 24),

        GradientButton(
          label: 'Generate my body model',
          icon: Icons.auto_awesome_rounded,
          onPressed: photo != null ? onSubmit : null,
        ),
      ]),
    );
  }

  void _showSourcePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36, height: 3,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.glassBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _SourceOption(
              icon: Icons.camera_alt_rounded,
              label: 'Take photo',
              onTap: () {
                Navigator.pop(context);
                onPickPhoto(ImageSource.camera);
              },
            ),
            const SizedBox(height: 12),
            _SourceOption(
              icon: Icons.photo_library_rounded,
              label: 'Choose from gallery',
              onTap: () {
                Navigator.pop(context);
                onPickPhoto(ImageSource.gallery);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceOption({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(children: [
            Icon(icon, color: AppColors.gold, size: 22),
            const SizedBox(width: 14),
            Text(label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                )),
          ]),
        ),
      );
}

// ── Step 3: Processing & Preview ──────────────────────────────────────────────
class _StepPreview extends StatelessWidget {
  final bool processing, done;
  final String? error, silhouetteUrl;
  final Animation<double> fade;
  final VoidCallback onRetry, onFinish;

  const _StepPreview({
    required this.processing,
    required this.done,
    required this.error,
    required this.silhouetteUrl,
    required this.fade,
    required this.onRetry,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(children: [
        if (processing) ...[
          const Spacer(),
          // Processing animation
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              gradient: AppColors.accent,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: AppColors.goldDark.withOpacity(0.20),
                blurRadius: 32, offset: const Offset(0, 8),
              )],
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Building your\nbody model...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'AI is removing the background\nand creating your silhouette',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const Spacer(),
        ] else if (error != null) ...[
          const Spacer(),
          const Text('⚠️', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 20),
          const Text(
            'Something went wrong',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const Spacer(),
          GradientButton(label: 'Try again', onPressed: onRetry),
        ] else if (done) ...[
          FadeTransition(
            opacity: fade,
            child: Column(children: [
              const Text(
                'Your model\nis ready! 🎉',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),

              // Silhouette preview
              Container(
                height: 320,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.glassBorder),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 16, offset: const Offset(0, 4),
                  )],
                ),
                clipBehavior: Clip.hardEdge,
                child: silhouetteUrl != null
                    ? Image.network(
                        silhouetteUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text('🧍', style: TextStyle(fontSize: 100)),
                        ),
                      )
                    : const Center(
                        child: Text('🧍', style: TextStyle(fontSize: 100)),
                      ),
              ),
              const SizedBox(height: 16),

              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 2, height: 36,
                    decoration: BoxDecoration(
                      gradient: AppColors.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Outfit try-ons will now be shown on your personal silhouette.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),

              GradientButton(
                label: 'Go to my wardrobe',
                icon: Icons.checkroom_rounded,
                onPressed: onFinish,
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Photo guide widget ────────────────────────────────────────────────────────

class _PhotoGuide extends StatelessWidget {
  const _PhotoGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text('📸  Photo tips',
                  style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          _Tip(icon: '🧍', text: 'Stand straight, full body visible — head to feet'),
          _Tip(icon: '💡', text: 'Good lighting — brightly lit room, face the light'),
          _Tip(icon: '🪟', text: 'Plain background — plain wall works best'),
          _Tip(icon: '👕', text: 'Wear fitted clothes — baggy clothes hide body shape'),
          _Tip(icon: '🤳', text: 'Arms slightly away from body — don\'t cross them'),
          _Tip(icon: '📱', text: 'Portrait orientation — hold phone upright, not sideways'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withOpacity(0.15)),
            ),
            child: const Row(children: [
              Text('✗', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Avoid: group photos, mirrors, dark rooms, full-body outfits that hide your shape',
                  style: TextStyle(
                      color: Colors.redAccent, fontSize: 11, height: 1.4),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final String icon, text;
  const _Tip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4)),
            ),
          ],
        ),
      );
}
