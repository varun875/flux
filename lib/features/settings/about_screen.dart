import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_version.dart';
import '../../core/theme/flux_theme.dart';
import '../../core/widgets/flux_widgets.dart';
import '../../core/widgets/flux_animations.dart';
import '../../l10n/app_localizations.dart';
import 'licenses.dart';

/// About — playful sticker-paper redesign.
///
/// Dotted background, large app icon sticker, sticker-style feature
/// chips, and licenses laid out as soft cards. No bottom cutoff.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  // Sticker palette.
  static const _stickerMint = Color(0xFFA0E7E5);
  static const _stickerLime = Color(0xFFB5E48C);
  static const _stickerSand = Color(0xFFFFD6A5);
  static const _stickerPeach = Color(0xFFFFB4A2);
  static const _stickerLavender = Color(0xFFBDB2FF);

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: flux.background,
        body: FluxDottedBackground(
          child: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Positioned(
                  left: 20,
                  top: 48,
                  child: FluxBackButton(onTap: () => context.pop()),
                ),
                const Positioned(
                  left: 20,
                  top: 100,
                  child: FluxTitle(title: 'About'),
                ),
                Positioned.fill(
                  left: 20,
                  right: 20,
                  top: 156,
                  child: ListView(
                    padding: EdgeInsets.only(bottom: bottomSafe + 24),
                    cacheExtent: 500,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // Hero — app icon + version.
                      BouncyFadeSlide(
                        delay: FluxDurations.staggerStep * 0,
                        child: Center(
                          child: Column(
                            children: [
                              const _AppIconSticker(),
                              const SizedBox(height: 22),
                              Text(
                                'Flux',
                                style: textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${AppLocalizations.of(context)!.version} ${AppVersion.version}',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: flux.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                child: Text(
                                  AppLocalizations.of(context)!.yourPrivateAI,
                                  textAlign: TextAlign.center,
                                  style: textTheme.bodyLarge?.copyWith(
                                    color: flux.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Description card.
                      BouncyFadeSlide(
                        delay: FluxDurations.staggerStep * 1,
                        child: _AboutCard(
                          children: [
                            Text(
                              'About Flux',
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Flux is your private AI assistant that runs entirely on your device. '
                              'No data is sent to the cloud, ensuring complete privacy and security. '
                              'Powered by state-of-the-art open-source models, Flux brings '
                              'intelligent conversation to your fingertips while keeping '
                              'your data local and secure.',
                              style: textTheme.bodyMedium?.copyWith(
                                color: flux.textSecondary,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      // Features — sticker rows.
                      const _SectionLabel(label: 'Key Features'),
                      const SizedBox(height: 12),
                      const _FeatureSticker(
                        icon: Icons.security,
                        title: '100% Private',
                        description:
                            'All processing happens on your device',
                        stickerColor: _stickerMint,
                      ),
                      const SizedBox(height: 10),
                      const _FeatureSticker(
                        icon: Icons.offline_bolt,
                        title: 'Works Offline',
                        description: 'No internet connection required',
                        stickerColor: _stickerSand,
                      ),
                      const SizedBox(height: 10),
                      const _FeatureSticker(
                        icon: Icons.memory,
                        title: 'Local Models',
                        description: 'Powered by open-source AI models',
                        stickerColor: _stickerLime,
                      ),
                      const SizedBox(height: 10),
                      const _FeatureSticker(
                        icon: Icons.devices,
                        title: 'Cross-Platform',
                        description:
                            'Available on mobile, tablet, and desktop',
                        stickerColor: _stickerLavender,
                      ),

                      const SizedBox(height: 30),

                      // Licenses.
                      const _SectionLabel(label: 'Licenses'),
                      const SizedBox(height: 12),
                      for (int i = 0; i < FluxLicenses.all.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _LicenseTile(
                          name: FluxLicenses.all[i].name,
                          type: FluxLicenses.all[i].type,
                          stickerColor: i.isEven
                              ? _stickerPeach
                              : _stickerLavender,
                          onTap: () => context.push(
                            '/settings/about/license/${FluxLicenses.all[i].id}',
                          ),
                        ),
                      ],
                    ],
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

class _AppIconSticker extends StatelessWidget {
  const _AppIconSticker();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 112,
      height: 112,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFFEFEFEF) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  final List<Widget> children;
  const _AboutCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _FeatureSticker extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color stickerColor;

  const _FeatureSticker({
    required this.icon,
    required this.title,
    required this.description,
    required this.stickerColor,
  });

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      decoration: BoxDecoration(
        color: flux.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: flux.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _StickerChip(color: stickerColor, icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseTile extends StatelessWidget {
  final String name;
  final String type;
  final Color stickerColor;
  final VoidCallback onTap;

  const _LicenseTile({
    required this.name,
    required this.type,
    required this.stickerColor,
    required this.onTap,
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
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        decoration: BoxDecoration(
          color: flux.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: flux.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            _StickerChip(color: stickerColor, icon: Icons.description_rounded),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(type, style: textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20,
                color: flux.textSecondary.withValues(alpha: 0.55)),
          ],
        ),
      ),
    );
  }
}

/// Sticker chip — colored squircle with white die-cut outline + shadow.
class _StickerChip extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _StickerChip({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
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
          Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Icon(icon, size: 20, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
