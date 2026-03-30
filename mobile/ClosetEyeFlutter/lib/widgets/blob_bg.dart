import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Warm sand background with soft morning-light gold ambient glow.
/// Light, airy, and premium — like natural linen with morning sunlight.
class BlobBg extends StatelessWidget {
  final Widget child;

  const BlobBg({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── 1. Warm ivory sand base ───────────────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        ),

        // ── 2. Soft gold morning light — upper left (like a window) ───────
        Positioned(
          top: -size.height * 0.12,
          left: -size.width * 0.15,
          child: Container(
            width: size.width * 0.85,
            height: size.width * 0.85,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.gold.withOpacity(0.10),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // ── 3. Soft warm blush — bottom right (depth & warmth) ────────────
        Positioned(
          bottom: -size.height * 0.08,
          right: -size.width * 0.15,
          child: Container(
            width: size.width * 0.7,
            height: size.width * 0.7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.goldMid.withOpacity(0.06),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // ── 4. Content ────────────────────────────────────────────────────
        child,
      ],
    );
  }
}
