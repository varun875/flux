import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// ANIMATION DURATIONS
// ============================================================================
class FluxDurations {
  static const Duration micro = Duration(milliseconds: 30);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration pageTransition = Duration(milliseconds: 500);
  static const Duration staggerStep = Duration(milliseconds: 40);
  static const Duration tap = Duration(milliseconds: 200);
}

// ============================================================================
// CURVES
// ============================================================================
class FluxCurves {
  static const Curve smooth = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Curve gentle = Cubic(0.25, 0.1, 0.25, 1.0);
}

// ============================================================================
// BOUNCY TAP - Snap feedback on tap
// ============================================================================
class BouncyTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDown;

  const BouncyTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleDown = 0.85,
  });

  @override
  State<BouncyTap> createState() => _BouncyTapState();
}

class _BouncyTapState extends State<BouncyTap>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: FluxDurations.tap,
      reverseDuration: FluxDurations.tap,
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleDown).animate(
      CurvedAnimation(
        parent: _controller,
        curve: FluxCurves.gentle,
        reverseCurve: FluxCurves.gentle,
      ),
    );
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap != null || widget.onLongPress != null) {
      HapticFeedback.lightImpact();
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.onTap != null) {
      _controller.reverse();
      widget.onTap!();
    }
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  void _onLongPress() {
    HapticFeedback.heavyImpact();
    _controller.reverse().then((_) {
      widget.onLongPress!();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onLongPress: widget.onLongPress != null ? _onLongPress : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

// ============================================================================
// BOUNCY FADE SLIDE - Smooth entrance
// ============================================================================
class BouncyFadeSlide extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double slideOffset;
  final Axis slideDirection;

  const BouncyFadeSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = FluxDurations.normal,
    this.slideOffset = 40.0,
    this.slideDirection = Axis.vertical,
  });

  @override
  State<BouncyFadeSlide> createState() => _BouncyFadeSlideState();
}

class _BouncyFadeSlideState extends State<BouncyFadeSlide>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = FluxCurves.gentle.transform(_controller.value);
        
        final offset = widget.slideDirection == Axis.vertical
            ? Offset(0, widget.slideOffset * (1.0 - t))
            : Offset(widget.slideOffset * (1.0 - t), 0);
            
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: offset,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ============================================================================
// FLUX PAGE TRANSITION (Universal Peer-to-Peer slide)
// ============================================================================
class FluxPageTransition extends StatelessWidget {
  final Animation<double> primaryAnimation;
  final Animation<double>? secondaryAnimation;
  final bool isForwardLayout;
  final Widget child;

  const FluxPageTransition({
    super.key,
    required this.primaryAnimation,
    this.secondaryAnimation,
    required this.isForwardLayout,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([primaryAnimation, secondaryAnimation]),
      builder: (context, child) {
        bool isForeground = true;
        final double t = primaryAnimation.value;
        double s = 0.0;

        if (secondaryAnimation != null && secondaryAnimation!.status != AnimationStatus.dismissed) {
          isForeground = false;
          s = secondaryAnimation!.value;
        } else if (secondaryAnimation == null && primaryAnimation.status == AnimationStatus.reverse) {
          isForeground = false;
          s = 1.0 - primaryAnimation.value;
        }

        const curve = FluxCurves.smooth;
        
        double offsetValue = 0.0;
        Widget finalChild = child!;

        if (isForeground) {
          final curvedT = curve.transform(t);
          offsetValue = (isForwardLayout ? 0.65 : -0.65) * (1.0 - curvedT);
          
          if (curvedT <= 0.15) {
            finalChild = Opacity(opacity: 0.0, child: finalChild);
          } else {
            final p = ((curvedT - 0.15) / 0.85).clamp(0.0, 1.0);
            if (p < 1.0) {
              finalChild = Opacity(opacity: p, child: finalChild);
            }
          }
        } else {
          final curvedS = curve.transform(s);
          offsetValue = (isForwardLayout ? -0.3 : 0.3) * curvedS;
          
          if (curvedS > 0.01) {
            final darkenAmount = curvedS * 0.12;
            finalChild = Transform.scale(
              scale: 1.0 - curvedS * 0.02,
              child: Stack(
                children: [
                  child,
                  Positioned.fill(
                    child: Container(color: Colors.black.withValues(alpha: darkenAmount)),
                  ),
                ],
              ),
            );
          }
        }

        return Transform.translate(
          offset: Offset(offsetValue * MediaQuery.of(context).size.width, 0),
          child: finalChild,
        );
      },
      child: child,
    );
  }
}
