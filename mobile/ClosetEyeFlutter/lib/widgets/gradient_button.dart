import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';

class GradientButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;
  final IconData? icon;
  final LinearGradient? gradient;

  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.height = 56,
    this.icon,
    this.gradient,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _press;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scale = Tween(begin: 1.0, end: 0.97).animate(
        CurvedAnimation(parent: _press, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down(_) {
    if (widget.onPressed != null && !widget.loading) _press.forward();
  }

  void _up(_) {
    _press.reverse();
    HapticFeedback.selectionClick();
    widget.onPressed?.call();
  }

  void _cancel() => _press.reverse();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final grad = widget.gradient ?? AppColors.accent;

    // Disabled gradient — warm light gray on sand bg
    const disabledGrad = LinearGradient(
      colors: [Color(0xFFE0D8CC), Color(0xFFD4CCBE)],
    );

    return GestureDetector(
      onTapDown: _down,
      onTapUp: enabled ? _up : null,
      onTapCancel: _cancel,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          height: widget.height,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: enabled ? grad : disabledGrad,
            borderRadius: BorderRadius.circular(14),
            // Single clean shadow — directional, no glow
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppColors.goldDark.withOpacity(0.20),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: widget.loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: AppColors.textPrimary,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon,
                            color: enabled
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            size: 18),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: enabled
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
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
