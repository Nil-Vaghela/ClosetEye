import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/theme.dart';
import '../widgets/blob_bg.dart';
import '../widgets/gradient_button.dart';
import '../widgets/app_text_field.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  late AnimationController _card;
  late Animation<Offset> _cardSlide;
  late Animation<double> _cardFade;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    _card = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _cardSlide = Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(
        CurvedAnimation(parent: _card, curve: Curves.easeOutCubic));
    _cardFade = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _card, curve: Curves.easeIn));
    Future.delayed(const Duration(milliseconds: 300), _card.forward);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _card.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (!phone.startsWith('+') || phone.length < 8) {
      setState(() => _error = 'Include country code  e.g. +1 555 000 1234');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      if (Platform.isIOS) {
        const channel = MethodChannel('drape/phone_auth');
        final verificationId = await channel.invokeMethod<String>(
          'verifyPhoneNumber', {'phoneNumber': phone});
        if (!mounted) return;
        setState(() => _loading = false);
        Navigator.push(context,
            MaterialPageRoute(builder: (_) =>
                OtpScreen(phoneNumber: phone, verificationId: verificationId)));
      } else {
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phone,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (credential) async {
            if (!mounted) return;
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) =>
                    OtpScreen(phoneNumber: phone, autoCredential: credential)));
          },
          verificationFailed: (e) {
            if (!mounted) return;
            setState(() { _loading = false; _error = e.message ?? 'Verification failed'; });
          },
          codeSent: (verificationId, _) {
            if (!mounted) return;
            setState(() => _loading = false);
            Navigator.push(context,
                MaterialPageRoute(builder: (_) =>
                    OtpScreen(phoneNumber: phone, verificationId: verificationId)));
          },
          codeAutoRetrievalTimeout: (_) {},
        );
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message ?? 'Verification failed'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: BlobBg(
          child: Column(children: [
            // ── Hero ────────────────────────────────────────────────────
            Expanded(
              flex: 5,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(height: 60),

                  // Logo mark
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: AppColors.accent,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.goldDark.withOpacity(0.28),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('👗', style: TextStyle(fontSize: 40)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Brand
                  ShaderMask(
                    shaderCallback: (b) => AppColors.accent.createShader(b),
                    child: const Text(
                      'DRAPE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your AI fashion assistant',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Feature pills — restrained
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _Pill('Scan clothes'),
                    const SizedBox(width: 8),
                    _Pill('AI styling'),
                    const SizedBox(width: 8),
                    _Pill('Try-on'),
                  ]),
                ]),
              ),
            ),

            // ── Glass bottom sheet ────────────────────────────────────────
            SlideTransition(
              position: _cardSlide,
              child: FadeTransition(
                opacity: _cardFade,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(
                        28, 28, 28,
                        MediaQuery.of(context).viewInsets.bottom +
                            MediaQuery.of(context).padding.bottom + 32,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.surface, // solid white sheet
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(28)),
                        border: Border(
                          top:   BorderSide(color: AppColors.glassBorder),
                          left:  BorderSide(color: AppColors.glassBorder),
                          right: BorderSide(color: AppColors.glassBorder),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Handle
                          Center(
                            child: Container(
                              width: 32, height: 3,
                              decoration: BoxDecoration(
                                color: AppColors.glassBorder,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          const Text(
                            'Sign in',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "We'll send a one-time code to your number",
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 22),

                          AppTextField(
                            controller: _phoneCtrl,
                            hint: '+1 555 000 1234',
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d+\s\-()]')),
                            ],
                            prefix: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14),
                              child: Text('📱',
                                  style: TextStyle(
                                      fontSize: 18,
                                      color: AppColors.textSecondary)),
                            ),
                          ),

                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: AppColors.error.withOpacity(0.25)),
                              ),
                              child: Row(children: [
                                Icon(Icons.error_outline_rounded,
                                    color: AppColors.error, size: 15),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_error!,
                                      style: TextStyle(
                                          color: AppColors.error,
                                          fontSize: 12)),
                                ),
                              ]),
                            ),
                          ],

                          const SizedBox(height: 22),
                          GradientButton(
                            label: 'Continue',
                            icon: Icons.arrow_forward_rounded,
                            loading: _loading,
                            onPressed: _loading ? null : _sendCode,
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              'By continuing you agree to our Terms & Privacy Policy',
                              style: TextStyle(
                                color: AppColors.textHint,
                                fontSize: 11,
                                letterSpacing: 0.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  const _Pill(this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.glassMid,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      );
}
