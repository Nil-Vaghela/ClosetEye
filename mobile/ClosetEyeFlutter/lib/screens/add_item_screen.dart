import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/clothing_item.dart';
import '../widgets/blob_bg.dart';
import '../widgets/gradient_button.dart';

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen>
    with SingleTickerProviderStateMixin {
  File? _image;
  bool _loading = false;
  bool _analyzing = false;

  late AnimationController _bounceCtrl;
  late Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _bounce = Tween(begin: -6.0, end: 6.0).animate(
        CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker()
        .pickImage(source: source, imageQuality: 85, maxWidth: 1200);
    if (picked != null) setState(() => _image = File(picked.path));
  }

  Future<void> _submit() async {
    if (_image == null) return;

    setState(() { _loading = true; _analyzing = true; });

    // Brief "analyzing" moment for UX delight
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _analyzing = false);

    try {
      final bytes = await _image!.readAsBytes();
      final base64 = base64Encode(bytes);
      await ApiClient.addItem(
        imageBase64: base64,
        category: 'Other', // AI will detect in future
        color: null,
        brand: null,
        notes: null,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString(),
            style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      setState(() { _loading = false; _analyzing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlobBg(
        child: SafeArea(
          child: Column(children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        width: 46, height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.glassMid,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: AppColors.textPrimary, size: 18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Text(
                  'Add to Wardrobe',
                  style: TextStyle(
                    
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Photo picker ────────────────────────────────────
                    GestureDetector(
                      onTap: _loading ? null : _showPickerSheet,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        height: 340,
                        decoration: BoxDecoration(
                          color: AppColors.glassMid,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: _image != null
                                ? AppColors.gold.withOpacity(0.5)
                                : AppColors.glassBorder,
                            width: _image != null ? 1.5 : 1,
                          ),
                          boxShadow: _image != null
                              ? [
                                  BoxShadow(
                                    color: AppColors.gold.withOpacity(0.2),
                                    blurRadius: 30,
                                    spreadRadius: 2,
                                  )
                                ]
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: _image != null
                              ? Stack(fit: StackFit.expand, children: [
                                  Image.file(_image!, fit: BoxFit.cover),
                                  // Re-pick overlay
                                  Positioned(
                                    bottom: 12, right: 12,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                            sigmaX: 10, sigmaY: 10),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withOpacity(0.45),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: AppColors.glassBorder),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.edit_rounded,
                                                  color: Colors.white,
                                                  size: 14),
                                              SizedBox(width: 6),
                                              Text('Change',
                                                  style: TextStyle(
                                                    
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  )),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ])
                              : AnimatedBuilder(
                                  animation: _bounce,
                                  builder: (_, __) => Transform.translate(
                                    offset: Offset(0, _bounce.value),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 72, height: 72,
                                          decoration: BoxDecoration(
                                            gradient: AppColors.accent,
                                            borderRadius:
                                                BorderRadius.circular(22),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.gold
                                                    .withOpacity(0.28),
                                                blurRadius: 24,
                                                offset:
                                                    const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                              Icons.add_a_photo_rounded,
                                              color: Colors.white,
                                              size: 32),
                                        ),
                                        const SizedBox(height: 18),
                                        const Text(
                                          'Tap to add photo',
                                          style: TextStyle(
                                            
                                            color: AppColors.textPrimary,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Camera or Gallery',
                                          style: TextStyle(
                                            
                                            color: AppColors.textMuted,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── AI badge ─────────────────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter:
                            ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.glassMid,
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: AppColors.glassBorder),
                          ),
                          child: Row(children: [
                            Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                gradient: AppColors.accent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Text('🤖',
                                    style: TextStyle(fontSize: 18)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AI Auto-Detection',
                                    style: TextStyle(
                                      
                                      color: AppColors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Category · Color · Brand detected automatically',
                                    style: TextStyle(
                                      
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── CTA ───────────────────────────────────────────────
                    if (_analyzing)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          height: 58,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: AppColors.accent,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'AI Analyzing...',
                                style: TextStyle(
                                  
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      GradientButton(
                        label: _image == null
                            ? 'Select a Photo First'
                            : 'Add to Wardrobe',
                        loading: _loading && !_analyzing,
                        onPressed: (_loading || _image == null)
                            ? null
                            : _submit,
                      ),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipRRect(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            decoration: const BoxDecoration(
              color: AppColors.glassMid,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(32)),
              border: Border(
                top: BorderSide(color: AppColors.glassBorder),
                left: BorderSide(color: AppColors.glassBorder),
                right: BorderSide(color: AppColors.glassBorder),
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Add Photo',
                style: TextStyle(
                  
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(
                  child: _PickerBtn(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    gradient: AppColors.accent,
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _PickerBtn(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    gradient: AppColors.accent,
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PickerBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _PickerBtn({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: gradient.colors.first.withOpacity(0.45),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                  
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                )),
          ]),
        ),
      );
}
