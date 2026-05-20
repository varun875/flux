import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_mode_provider.dart';
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

class FluxShell extends ConsumerStatefulWidget {
  final Widget child;

  const FluxShell({super.key, required this.child});

  @override
  ConsumerState<FluxShell> createState() => _FluxShellState();
}

class _FluxShellState extends ConsumerState<FluxShell> {
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
    final appMode = ref.watch(appModeProvider);
    final isDesktop = context.isDesktop;
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;

    final body = TabNavigationInfo(
      previousIndex: _previousIndex,
      currentIndex: _currentIndex,
      child: isDesktop ? ResponsiveCenter(child: widget.child) : widget.child,
    );

    return Scaffold(
      backgroundColor: flux.background,
      resizeToAvoidBottomInset: false,
      body: Row(
        children: [
          if (isDesktop)
            _DesktopSidebar(
              currentMode: appMode,
              onModeChanged: (mode) {
                ref.read(appModeProvider.notifier).setMode(mode);
              },
              flux: flux,
            ),
          Expanded(
            child: FluxAuraBackground(
              primary: appMode == AppMode.fluxCode ? flux.accentWarm : flux.accent,
              secondary: flux.accentWarm,
              intensity: 0.07,
              child: RepaintBoundary(child: body),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  final AppMode currentMode;
  final ValueChanged<AppMode> onModeChanged;
  final FluxColorsExtension flux;

  const _DesktopSidebar({
    required this.currentMode,
    required this.onModeChanged,
    required this.flux,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: flux.background,
        border: Border(right: BorderSide(color: flux.border, width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 48),
          _SidebarItem(
            icon: Icons.bubble_chart_rounded,
            isSelected: currentMode == AppMode.flux,
            onTap: () => onModeChanged(AppMode.flux),
            flux: flux,
            tooltip: 'Flux',
          ),
          const SizedBox(height: 20),
          _SidebarItem(
            icon: Icons.code_rounded,
            isSelected: currentMode == AppMode.fluxCode,
            onTap: () => onModeChanged(AppMode.fluxCode),
            flux: flux,
            tooltip: 'Flux Code',
          ),
          const Spacer(),
          _SidebarItem(
            icon: Icons.settings_rounded,
            isSelected: false,
            onTap: () => context.push('/settings'),
            flux: flux,
            tooltip: 'Settings',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final FluxColorsExtension flux;
  final String tooltip;

  const _SidebarItem({
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.flux,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: BouncyTap(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isSelected ? flux.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            color: isSelected ? flux.background : flux.textSecondary,
            size: 24,
          ),
        ),
      ),
    );
  }
}
