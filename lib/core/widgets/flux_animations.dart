import 'package:flutter/material.dart';
import 'flux_shell.dart';

// ============================================================================
// ANIMATION DURATIONS
// ============================================================================
class FluxDurations {
  static const Duration micro = Duration(milliseconds: 30);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration pageTransition = Duration(milliseconds: 500);
  static const Duration reverseTransition = Duration(milliseconds: 300);
  static const Duration staggerStep = Duration(milliseconds: 40);
  static const Duration bouncy = Duration(milliseconds: 600);
  static const Duration tapDown = Duration(milliseconds: 60);
  static const Duration tapUp = Duration(milliseconds: 200);
}

// ============================================================================
// CURVES
// ============================================================================
class FluxCurves {
  static const Curve easeOut = Cubic(0.16, 1, 0.3, 1);
  static const Curve easeInOut = Cubic(0.87, 0, 0.13, 1);
  static const Curve bouncy = Cubic(0.68, -0.6, 0.32, 1.6);
  static const Curve superBouncy = Cubic(0.68, -0.8, 0.265, 1.8);
  static const Curve springy = Cubic(0.175, 0.885, 0.32, 1.275);
  static const Curve playful = Cubic(0.87, -0.41, 0.19, 1.44);
  static const Curve snappy = Cubic(0.0, 1.0, 0.0, 1.0);
  static const Curve gentleSpring = Cubic(0.2, 0.8, 0.2, 1);
  static const Curve elasticOut = Curves.elasticOut;
  static const Curve elasticIn = Curves.elasticIn;
  static const Curve bouncyElastic = Curves.elasticInOut;
  static const Curve smoothIn = Cubic(0.4, 0, 1, 1);
  static const Curve smoothOut = Cubic(0, 0, 0.2, 1);
  static const Curve decelerate = Curves.easeOutCirc;
  static const Curve emphasis = Curves.easeOutQuint;
  static const Curve popIn = Curves.easeOutBack;
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
      duration: FluxDurations.tapUp,
      reverseDuration: FluxDurations.tapDown,
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleDown).animate(
      CurvedAnimation(
        parent: _controller,
        curve: FluxCurves.springy,
        reverseCurve: FluxCurves.easeOut,
      ),
    );
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.onTap != null) {
      _controller.reverse(); // animate back, don't block the action
      widget.onTap!();       // fire immediately — no 200ms delay
    }
  }

  void _onTapCancel() {
    _controller.reverse();
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
      onLongPress: widget.onLongPress != null
          ? () {
              _controller.reverse().then((_) {
                widget.onLongPress!();
              });
            }
          : null,
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
        final easeT = FluxCurves.easeOut.transform(_controller.value);
        final t = FluxCurves.springy.transform(_controller.value);
        
        final offset = widget.slideDirection == Axis.vertical
            ? Offset(0, widget.slideOffset * (1.0 - t))
            : Offset(widget.slideOffset * (1.0 - t), 0);
            
        return Opacity(
          opacity: easeT.clamp(0.0, 1.0),
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
        double t = primaryAnimation.value;
        double s = 0.0;

        if (secondaryAnimation != null && secondaryAnimation!.status != AnimationStatus.dismissed) {
          isForeground = false;
          s = secondaryAnimation!.value;
        } else if (secondaryAnimation == null && primaryAnimation.status == AnimationStatus.reverse) {
          isForeground = false;
          s = 1.0 - primaryAnimation.value;
        }

        final curve = Curves.easeOutQuart;
        
        double offsetValue = 0.0;
        Widget finalChild = child!;

        if (isForeground) {
          final curvedT = curve.transform(t);
          offsetValue = (isForwardLayout ? 0.65 : -0.65) * (1.0 - curvedT);
          
          if (curvedT <= 0.25) {
            finalChild = Opacity(opacity: 0.0, child: finalChild);
          } else {
            final p = ((curvedT - 0.25) / 0.75).clamp(0.0, 1.0);
            if (p < 1.0) {
              finalChild = Opacity(opacity: p, child: finalChild);
            }
          }
        } else {
          final curvedS = curve.transform(s);
          offsetValue = (isForwardLayout ? -0.3 : 0.3) * curvedS;
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
