import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_version.dart';
import '../../core/theme/flux_theme.dart';
import '../../core/widgets/flux_widgets.dart';
import '../../core/widgets/flux_animations.dart';
import '../../l10n/app_localizations.dart';

/// Settings — playful sticker-paper redesign.
///
/// Dotted background, colorful sticker-style icon chips, and content
/// that scrolls all the way to the safe-area edge (no artificial
/// bottom cutoff).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showTokenSpeed = false;

  // Sticker palette — same vibe as Creations.
  static const _stickerPeach = Color(0xFFFFB4A2);
  static const _stickerMint = Color(0xFFA0E7E5);
  static const _stickerSand = Color(0xFFFFD6A5);
  static const _stickerCoral = Color(0xFFFFADAD);

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
          () => _showTokenSpeed = prefs.getBool('showTokenSpeed') ?? false);
    }
  }

  Future<void> _toggleTokenSpeed(bool value) async {
    HapticFeedback.selectionClick();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showTokenSpeed', value);
    if (mounted) setState(() => _showTokenSpeed = value);
  }

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final loc = AppLocalizations.of(context)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: flux.background,
        body: Stack(
          children: [
              Positioned(
                left: 20,
                top: topPadding + 48,
                child: FluxBackButton(onTap: () => context.pop()),
              ),
              Positioned(
                left: 20,
                top: topPadding + 100,
                child: FluxTitle(title: loc.settings),
              ),
              Positioned.fill(
                top: topPadding + 150,
                left: 20,
                right: 20,
                child: ListView(
                  padding: EdgeInsets.only(bottom: bottomSafe + 24),
                  cacheExtent: 500,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    const _SectionLabel(label: 'General'),
                    const SizedBox(height: 10),
                    _StickerTile(
                      title: 'Token Speed',
                      subtitle: 'Show tok/s on chat and editor',
                      icon: Icons.speed_rounded,
                      stickerColor: _stickerMint,
                      trailing: CupertinoSwitch(
                        value: _showTokenSpeed,
                        activeTrackColor: flux.textPrimary,
                        onChanged: _toggleTokenSpeed,
                      ),
                      onTap: () => _toggleTokenSpeed(!_showTokenSpeed),
                    ),
                    const SizedBox(height: 28),
                    const _SectionLabel(label: 'Data'),
                    const SizedBox(height: 10),
                    _StickerTile(
                      title: loc.clearCache,
                      subtitle: loc.removeTemporaryFiles,
                      icon: Icons.delete_sweep_rounded,
                      stickerColor: _stickerCoral,
                      destructive: true,
                      onTap: () => _confirmClearCache(context, textTheme),
                    ),
                    const SizedBox(height: 28),
                    const _SectionLabel(label: 'About'),
                    const SizedBox(height: 10),
                    _StickerTile(
                      title: loc.aboutFlux,
                      subtitle: '${loc.version} ${AppVersion.version}',
                      icon: Icons.info_rounded,
                      stickerColor: _stickerPeach,
                      onTap: () => context.push('/settings/about'),
                      showChevron: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  void _confirmClearCache(BuildContext context, TextTheme textTheme) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final loc = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: flux.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(loc.clearCacheQuestion, style: textTheme.headlineMedium),
        content: Text(loc.clearCacheMessage, style: textTheme.bodySmall),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            child: Text(loc.cancel,
                style:
                    textTheme.bodyMedium?.copyWith(color: flux.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
              final prefs = await SharedPreferences.getInstance();
              for (final key in [
                'onboarded',
                'selectedModelId',
                'language'
              ]) {
                await prefs.remove(key);
              }
              await Hive.box('chats').clear();
              await Hive.box('creations').clear();
              await Hive.box('settings').clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(loc.cacheCleared,
                        style: textTheme.bodySmall),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    margin: const EdgeInsets.all(20),
                  ),
                );
              }
            },
            child: Text(loc.confirm,
                style: textTheme.bodyMedium
                    ?.copyWith(color: Colors.red, fontWeight: FontWeight.w400)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        label.toUpperCase(),
        style: textTheme.labelLarge?.copyWith(
          color: flux.textSecondary,
          letterSpacing: 1.4,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Sticker-style settings tile: a colored, die-cut chip on the left and
/// a soft drop shadow under the whole card so it pops off the page.
class _StickerTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color stickerColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;
  final bool showChevron;

  const _StickerTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.stickerColor,
    this.onTap,
    this.trailing,
    this.destructive = false,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BouncyTap(
      onTap: onTap,
      scaleDown: 0.97,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: BoxDecoration(
          color: flux.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: flux.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Sticker chip — colored squircle with die-cut white border.
            _StickerChip(
              color: stickerColor,
              icon: icon,
              destructive: destructive,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyLarge?.copyWith(
                      color: destructive ? Colors.red : flux.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: textTheme.bodySmall),
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (showChevron)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: flux.textSecondary.withValues(alpha: 0.55),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reusable sticker chip — colored squircle with white "die-cut" outline.
class _StickerChip extends StatelessWidget {
  final Color color;
  final IconData icon;
  final bool destructive;

  const _StickerChip({
    required this.color,
    required this.icon,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // White die-cut border + shadow.
          Container(
            decoration: ShapeDecoration(
              color: isDark ? const Color(0xFFEFEFEF) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          // Colored face.
          Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Icon(
                icon,
                size: 20,
                color:
                    destructive ? Colors.red.shade900 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
