import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/responsive.dart';
import '../theme/flux_theme.dart';
import 'flux_animations.dart';

class TabNavigationInfo extends InheritedWidget {
  final int previousIndex;
  final int currentIndex;

  const TabNavigationInfo({
    super.key,
    required this.previousIndex,
    required this.currentIndex,
    required super.child,
  });

  static TabNavigationInfo? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TabNavigationInfo>();
  }

  @override
  bool updateShouldNotify(TabNavigationInfo oldWidget) {
    return previousIndex != oldWidget.previousIndex ||
        currentIndex != oldWidget.currentIndex;
  }
}

class FluxShell extends StatefulWidget {
  final Widget child;

  const FluxShell({super.key, required this.child});

  @override
  State<FluxShell> createState() => _FluxShellState();
}

class _FluxShellState extends State<FluxShell> {
  int _currentIndex = 0;
  int _previousIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextIndex = _getIndexFromLocation(GoRouterState.of(context).location);
    if (nextIndex != _currentIndex) {
      _previousIndex = _currentIndex;
      _currentIndex = nextIndex;
    }
  }

  int _getIndexFromLocation(String location) {
    if (location.startsWith('/home')) {
      return 0;
    }
    if (location.startsWith('/creations')) {
      return 1;
    }
    if (location.startsWith('/settings')) {
      return 2;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final child = TabNavigationInfo(
      previousIndex: _previousIndex,
      currentIndex: _currentIndex,
      child: context.isDesktop
          ? ResponsiveCenter(child: widget.child)
          : widget.child,
    );

    return Scaffold(
      backgroundColor: flux.background,
      resizeToAvoidBottomInset: false,
      body: FluxAuraBackground(
        primary: flux.accent,
        secondary: flux.accentWarm,
        intensity: 0.07,
        child: RepaintBoundary(child: child),
      ),
    );
  }
}
