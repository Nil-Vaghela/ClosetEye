import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../widgets/blob_bg.dart';
import '../widgets/gradient_button.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';
import 'profile_setup_screen.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  final String? verificationId;
  final PhoneAuthCredential? autoCredential;

  const OtpScreen({
    super.key,
    required this.phoneNumber,
    this.verificationId,
    this.autoCredential,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  String _otp = '';
  bool _loading = false;
  String? _error;
  int _countdown = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _ctrl.addListener(() {
      setState(() => _otp = _ctrl.text);
      if (_ctrl.text.length == 6) _verifyCode();
    });
    if (widget.autoCredential != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _verify(widget.autoCredential!));
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) {
        t.cancel();
        if (mounted) setState(() => _countdown = 0);
      } else {
        if (mounted) setState(() => _countdown--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    if (_otp.length != 6 || widget.verificationId == null) return;
    final credential = PhoneAuthProvider.credential(
      verificationId: widget.verificationId!,
      smsCode: _otp,
    );
    await _verify(credential);
  }

  Future<void> _verify(PhoneAuthCredential credential) async {
    setState(() { _loading = true; _error = null; });
    try {
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await result.user!.getIdToken();
      if (!mounted) return;

      final auth = context.read<AppAuthProvider>();
      await auth.signInWithFirebaseToken(idToken!);
      if (!mounted) return;

      if (auth.error != null) {
        setState(() { _loading = false; _error = auth.error; });
        return;
      }

      final dest = (auth.user?.isNewUser ?? true)
          ? const ProfileSetupScreen()
          : const HomeScreen();
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => dest), (_) => false);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message ?? 'Invalid code. Try again.';
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: Scaffold(
        body: BlobBg(
          child: SafeArea(
            child: Stack(children: [
              // Invisible keyboard input
              Opacity(
                opacity: 0,
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                ),
              ),

              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  28, 24, 28,
                  MediaQuery.of(context).viewInsets.bottom + 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.glassMid,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: AppColors.textPrimary, size: 16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 44),

                    Text(
                      'Enter\nthe code',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                        children: [
                          const TextSpan(text: 'Sent to '),
                          TextSpan(
                            text: widget.phoneNumber,
                            style: TextStyle(
                              color: AppColors.goldMid,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 44),

                    // ── OTP boxes ───────────────────────────────────────
                    GestureDetector(
                      onTap: () => _focusNode.requestFocus(),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (i) {
                          final filled = _otp.length > i;
                          final active = _otp.length == i && !_loading;
                          return _OtpBox(
                            char: filled ? _otp[i] : '',
                            isActive: active,
                            isFilled: filled,
                          );
                        }),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
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
                                    color: AppColors.error, fontSize: 12)),
                          ),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 32),
                    GradientButton(
                      label: 'Verify',
                      loading: _loading,
                      onPressed: (_loading || _otp.length < 6) ? null : _verifyCode,
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: _countdown > 0
                          ? Text(
                              'Resend in ${_countdown}s',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 13),
                            )
                          : GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Text(
                                'Resend code',
                                style: TextStyle(
                                  color: AppColors.goldMid,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final String char;
  final bool isActive;
  final bool isFilled;

  const _OtpBox({
    required this.char,
    required this.isActive,
    required this.isFilled,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 44,
      height: 56,
      decoration: BoxDecoration(
        color: isFilled ? AppColors.glassBright : AppColors.glassMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.gold
              : isFilled
                  ? AppColors.gold.withOpacity(0.45)
                  : AppColors.glassBorder,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: Center(
        child: char.isEmpty
            ? (isActive
                ? Container(
                    width: 1.5,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  )
                : null)
            : Text(
                char,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
