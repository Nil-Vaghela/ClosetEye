import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../widgets/blob_bg.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'profile_setup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _main;
  late Animation<double> _fade;
  late Animation<double> _scale;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    _main = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));

    _scale = Tween(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _main,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)));
    _fade = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _main,
            curve: const Interval(0.0, 0.4, curve: Curves.easeIn)));
    _textFade = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _main,
            curve: const Interval(0.4, 0.9, curve: Curves.easeIn)));
    _textSlide = Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(
        CurvedAnimation(parent: _main,
            curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic)));

    _main.forward();
    Future.delayed(const Duration(milliseconds: 2400), _navigate);
  }

  void _navigate() {
    if (!mounted) return;
    final auth = context.read<AppAuthProvider>();
    Widget dest;
    if (!auth.isAuthenticated) {
      dest = const LoginScreen();
    } else if (auth.user?.isNewUser ?? true) {
      dest = const ProfileSetupScreen();
    } else {
      dest = const HomeScreen();
    }
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => dest,
      transitionDuration: const Duration(milliseconds: 600),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  void dispose() {
    _main.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlobBg(
        child: Center(
          child: AnimatedBuilder(
            animation: _main,
            builder: (_, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Logo mark ──────────────────────────────────────────
                FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        gradient: AppColors.accent,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.goldDark.withOpacity(0.30),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('👗', style: TextStyle(fontSize: 44)),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 26),

                // ── Brand name ─────────────────────────────────────────
                SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textFade,
                    child: Column(children: [
                      ShaderMask(
                        shaderCallback: (b) =>
                            AppColors.accent.createShader(b),
                        child: const Text(
                          'CLOSETEYE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'YOUR AI FASHION ASSISTANT',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 3.5,
                        ),
                      ),
                      // no changes needed — textMuted now dark on sand bg
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
