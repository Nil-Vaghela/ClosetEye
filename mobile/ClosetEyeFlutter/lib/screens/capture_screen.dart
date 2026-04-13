import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../widgets/gradient_button.dart';
import 'item_review_screen.dart';
import 'review_extracted_screen.dart';

class CaptureScreen extends StatefulWidget {
  final bool isShoppingMode;
  const CaptureScreen({super.key, this.isShoppingMode = false});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  File? _selectedPhoto;
  bool _extracting = false;
  String _extractStatus = '';

  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final photo = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1200,
    );
    if (photo != null) setState(() => _selectedPhoto = File(photo.path));
  }

  /// Multi-item extraction: send photo → AI detects all items → review screen
  Future<void> _scanOutfit() async {
    if (_selectedPhoto == null) return;

    setState(() {
      _extracting = true;
      _extractStatus = 'Analyzing your outfit…';
    });

    try {
      // Short delay for UX polish
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() => _extractStatus = 'Detecting clothing items…');

      final response = await ApiClient.extractItems(_selectedPhoto!);

      if (!mounted) return;
      setState(() => _extractStatus = 'Almost done…');
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewExtractedScreen.fromResponse(response),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _extractStatus = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  /// Legacy single-item flow (sends photo to rembg + AI detect → single review)
  void _addSingleItem() {
    if (_selectedPhoto != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ItemReviewScreen(
            photo: _selectedPhoto!,
            isShoppingMode: widget.isShoppingMode,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    // ── Extracting state: full-screen loading ──────────────────────────────
    if (_extracting) return _buildExtracting();

    // ── Photo selected: preview + actions ──────────────────────────────────
    if (_selectedPhoto != null) return _buildPreview();

    // ── Default: pick source ──────────────────────────────────────────────
    return _buildPicker();
  }

  Widget _buildExtracting() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Transform.scale(
                    scale: 0.9 + 0.1 * _pulse.value,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.accent,
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors.gold.withOpacity(0.3 * _pulse.value),
                            blurRadius: 30,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: const Center(
                          child: Text('✨', style: TextStyle(fontSize: 44))),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  _extractStatus,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'AI is identifying every piece in your photo.\nThis may take 30–60 seconds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(
                    backgroundColor: AppColors.glassBorder,
                    valueColor: AlwaysStoppedAnimation(AppColors.gold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => setState(() => _selectedPhoto = null),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.textPrimary, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Preview',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]),
          ),

          // Photo
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.file(_selectedPhoto!, fit: BoxFit.cover,
                    width: double.infinity),
              ),
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(children: [
              // Primary: Scan Outfit (multi-extract)
              GradientButton(
                label: 'Scan Outfit',
                icon: Icons.auto_awesome_rounded,
                onPressed: _scanOutfit,
              ),
              const SizedBox(height: 10),
              // Secondary: Add Single Item (legacy flow)
              GestureDetector(
                onTap: _addSingleItem,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: const Text(
                    'Add as Single Item',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _selectedPhoto = null),
                child: Text(
                  'Retake',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildPicker() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          // Header
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
                  child: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.textPrimary, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Add to Wardrobe',
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

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 40),
              child: Column(children: [
                // Hero icon
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: AppColors.accent,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Colors.white, size: 38),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Snap your outfit',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Take a full-body photo or pick one from your gallery.\n'
                  'AI will detect every piece you\'re wearing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 36),
                Row(children: [
                  Expanded(
                    child: _SourceCard(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      description: 'Take a photo',
                      onTap: () => _pick(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _SourceCard(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      description: 'Choose existing',
                      onTap: () => _pick(ImageSource.gallery),
                    ),
                  ),
                ]),
                const SizedBox(height: 28),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Icon(Icons.tips_and_updates_outlined,
                        color: AppColors.gold, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Full body photos work best — AI will detect '
                        'shirts, pants, shoes, accessories and more.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _SourceCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppColors.accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 14),
            Text(label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 3),
            Text(description,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                )),
          ]),
        ),
      );
}
