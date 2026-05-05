import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/model_service.dart';
import '../../core/models/hf_model.dart';
import '../../core/providers/download_provider.dart';
import '../../core/providers/model_provider.dart';
import '../../core/theme/flux_theme.dart';
import '../../core/widgets/flux_animations.dart';
import '../../l10n/app_localizations.dart';

// ============================================================================
// TYPOGRAPHY — v0.1.6 clean weights
// ============================================================================
class _AppTypography {
  static TextStyle heading(BuildContext context) => GoogleFonts.instrumentSans(
        fontSize: 25,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).extension<FluxColorsExtension>()!.textPrimary,
        height: 1.22,
        letterSpacing: 0,
      );

  static TextStyle description(BuildContext context) => GoogleFonts.instrumentSans(
        fontSize: 20,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).extension<FluxColorsExtension>()!.textSecondary,
        height: 1.22,
        letterSpacing: 0,
      );

  static TextStyle button(BuildContext context) => GoogleFonts.instrumentSans(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).extension<FluxColorsExtension>()!.background,
        height: 1.22,
        letterSpacing: 0,
      );

  static TextStyle backButton(BuildContext context) => GoogleFonts.instrumentSans(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).extension<FluxColorsExtension>()!.textSecondary,
        height: 1.22,
        letterSpacing: 0,
      );

  static TextStyle modelTitle(BuildContext context) => GoogleFonts.instrumentSans(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).extension<FluxColorsExtension>()!.textPrimary,
        letterSpacing: 0,
      );

  static TextStyle modelSubtitle(BuildContext context) => GoogleFonts.instrumentSans(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).extension<FluxColorsExtension>()!.textSecondary,
        letterSpacing: 0,
      );
}

// ============================================================================
// ASSETS
// ============================================================================
class _AppAssets {
  static const String backArrow = 'assets/images/back_arrow.svg';
}

// ============================================================================
// MAIN SCREEN
// ============================================================================
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _page = 0;
  bool _isNavigating = false;
  bool _isDownloading = false;
  bool _isForward = true;

  List<HFModel> _models = [];
  bool _isLoadingModels = true;
  HFModel? _selectedModel;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    final models = await ModelService.getRecommendedModels();
    if (mounted) {
      setState(() {
        _models = models;
        _isLoadingModels = false;
        if (models.isNotEmpty) _selectedModel = models.first;
      });
    }
  }

  void _onNext() async {
    if (_isNavigating || _page >= 4) return;

    setState(() {
      _isNavigating = true;
      _isForward = true;
      _page++;
    });

    await Future.delayed(const Duration(milliseconds: 450));
    if (mounted) setState(() => _isNavigating = false);
  }

  void _onBack() async {
    if (_isNavigating || _page <= 0) return;

    setState(() {
      _isNavigating = true;
      _isForward = false;
      _page--;
    });

    await Future.delayed(const Duration(milliseconds: 450));
    if (mounted) setState(() => _isNavigating = false);
  }

  Future<void> _onSkip() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);

    if (mounted) context.go('/home');
  }

  Future<void> _onFinish() async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    if (_selectedModel != null) {
      final url = ModelService.getDownloadUrl(_selectedModel!.id);
      ref.read(downloadProvider.notifier).startDownloadWithUrl(_selectedModel!, url);
      ref.read(selectedModelIdProvider.notifier).select(_selectedModel!.id);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);

    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final brightness = Theme.of(context).brightness;

    Widget currentSlide;
    switch (_page) {
      case 0:
        currentSlide = _WelcomeSlide(key: const ValueKey(0), onNext: _onNext, onSkip: _onSkip);
        break;
      case 1:
        currentSlide = _PrivacySlide(key: const ValueKey(1), onNext: _onNext, onBack: _onBack);
        break;
      case 2:
        currentSlide = _OfflineSlide(key: const ValueKey(2), onNext: _onNext, onBack: _onBack);
        break;
      case 3:
        currentSlide = _DownloadModelSlide(
          key: const ValueKey(3),
          models: _models,
          isLoading: _isLoadingModels,
          selectedModel: _selectedModel,
          onSelect: (model) => setState(() => _selectedModel = model),
          onNext: _onNext,
          onBack: _onBack,
        );
        break;
      case 4:
      default:
        currentSlide = _FinishSlide(key: const ValueKey(4), onFinish: _onFinish);
        break;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: brightness == Brightness.dark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: flux.background,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            reverseDuration: const Duration(milliseconds: 450),
            switchInCurve: Curves.linear,
            switchOutCurve: Curves.linear,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (child, animation) {
              return FluxPageTransition(
                primaryAnimation: animation,
                isForwardLayout: _isForward,
                child: child,
              );
            },
            child: currentSlide,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SLIDES — v0.1.6 layout, current animations
// ============================================================================

class _WelcomeSlide extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _WelcomeSlide({super.key, required this.onNext, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        const spacing = 60.0;
        const contentHeight = 31.0 + spacing + 44;
        final topPadding = ((screenHeight - contentHeight) / 2) + 60;
        final flux = Theme.of(context).extension<FluxColorsExtension>()!;

        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: topPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BouncyFadeSlide(
                    delay: const Duration(milliseconds: 100),
                    duration: const Duration(milliseconds: 600),
                    slideOffset: 20,
                    child: Text(
                      AppLocalizations.of(context)!.welcomeToFlux,
                      style: _AppTypography.heading(context),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: spacing),

                  BouncyFadeSlide(
                    delay: const Duration(milliseconds: 200),
                    duration: const Duration(milliseconds: 600),
                    slideOffset: 20,
                    child: _AnimatedButton(
                      text: AppLocalizations.of(context)!.start,
                      onPressed: onNext,
                    ),
                  ),

                  const SizedBox(height: 20),

                  BouncyFadeSlide(
                    delay: const Duration(milliseconds: 250),
                    duration: const Duration(milliseconds: 600),
                    slideOffset: 20,
                    child: BouncyTap(
                      onTap: onSkip,
                      scaleDown: 0.95,
                      child: Text(
                        AppLocalizations.of(context)!.skipSetup,
                        style: _AppTypography.backButton(context).copyWith(
                          color: flux.textSecondary.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PrivacySlide extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _PrivacySlide({super.key, required this.onNext, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        const spacing = 60.0;
        const contentHeight = 31.0 + 20 + 76 + spacing + 44;
        final topPadding = ((screenHeight - contentHeight) / 2) + 60;

        return Stack(
          children: [
            Positioned(
              left: 20,
              top: 74,
              child: BouncyFadeSlide(
                delay: Duration.zero,
                duration: const Duration(milliseconds: 400),
                slideOffset: 20,
                child: _BackButton(onPressed: onBack),
              ),
            ),

            Positioned(
              left: 20,
              right: 20,
              top: topPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BouncyFadeSlide(
                    delay: const Duration(milliseconds: 100),
                    duration: const Duration(milliseconds: 500),
                    slideOffset: 20,
                    child: Text(
                      AppLocalizations.of(context)!.weValuePrivacy,
                      style: _AppTypography.heading(context),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 20),

                  BouncyFadeSlide(
                    delay: const Duration(milliseconds: 150),
                    duration: const Duration(milliseconds: 500),
                    slideOffset: 20,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        AppLocalizations.of(context)!.privacyDescription,
                        style: _AppTypography.description(context),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                  SizedBox(height: spacing),

                  BouncyFadeSlide(
                    delay: const Duration(milliseconds: 200),
                    duration: const Duration(milliseconds: 500),
                    slideOffset: 20,
                    child: _AnimatedButton(
                      text: AppLocalizations.of(context)!.next,
                      onPressed: onNext,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OfflineSlide extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _OfflineSlide({super.key, required this.onNext, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        const spacing = 60.0;
        const contentHeight = 31.0 + 20 + 76 + spacing + 44;
        final topPadding = ((screenHeight - contentHeight) / 2) + 60;

        return Stack(
          children: [
            Positioned(
              left: 20,
              top: 74,
              child: BouncyFadeSlide(
                delay: Duration.zero,
                duration: const Duration(milliseconds: 400),
                slideOffset: 20,
                child: _BackButton(onPressed: onBack),
              ),
            ),

            Positioned(
              left: 20,
              right: 20,
              top: topPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BouncyFadeSlide(
                    delay: const Duration(milliseconds: 100),
                    duration: const Duration(milliseconds: 500),
                    slideOffset: 20,
                    child: Text(
                      AppLocalizations.of(context)!.fullyOffline,
                      style: _AppTypography.heading(context),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 20),

                  BouncyFadeSlide(
                    delay: const Duration(milliseconds: 150),
                    duration: const Duration(milliseconds: 500),
                    slideOffset: 20,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        AppLocalizations.of(context)!.offlineDescription,
                        style: _AppTypography.description(context),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                  SizedBox(height: spacing),

                  BouncyFadeSlide(
                    delay: const Duration(milliseconds: 200),
                    duration: const Duration(milliseconds: 500),
                    slideOffset: 20,
                    child: _AnimatedButton(
                      text: AppLocalizations.of(context)!.next,
                      onPressed: onNext,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DownloadModelSlide extends StatelessWidget {
  final List<HFModel> models;
  final bool isLoading;
  final HFModel? selectedModel;
  final Function(HFModel) onSelect;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _DownloadModelSlide({
    super.key,
    required this.models,
    required this.isLoading,
    required this.selectedModel,
    required this.onSelect,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    return Stack(
      children: [
        Positioned(
          left: 20,
          top: 74,
          child: BouncyFadeSlide(
            delay: Duration.zero,
            duration: const Duration(milliseconds: 400),
            slideOffset: 20,
            child: _BackButton(onPressed: onBack),
          ),
        ),

        Positioned(
          left: 20,
          top: 122,
          right: 20,
          child: BouncyFadeSlide(
            delay: const Duration(milliseconds: 100),
            duration: const Duration(milliseconds: 500),
            slideOffset: 20,
            child: Text(
              AppLocalizations.of(context)!.chooseModel,
              style: _AppTypography.heading(context),
            ),
          ),
        ),

        Positioned(
          left: 20,
          top: 173,
          right: 20,
          child: BouncyFadeSlide(
            delay: const Duration(milliseconds: 150),
            duration: const Duration(milliseconds: 500),
            slideOffset: 20,
            child: Text(
              AppLocalizations.of(context)!.chooseModelDescription,
              style: _AppTypography.description(context),
            ),
          ),
        ),

        Positioned(
          left: 20,
          top: 265,
          right: 20,
          bottom: 100,
          child: isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: flux.textPrimary,
                    strokeWidth: 2,
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: models.length,
                  cacheExtent: 150,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final model = models[index];
                    final isSelected = selectedModel?.id == model.id;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BouncyFadeSlide(
                        delay: Duration(milliseconds: 100 + index * 60),
                        duration: const Duration(milliseconds: 400),
                        slideOffset: 20,
                        child: BouncyTap(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            onSelect(model);
                          },
                          scaleDown: 0.95,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                            decoration: BoxDecoration(
                              color: flux.surface,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: isSelected ? flux.textPrimary : flux.border,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        model.name,
                                        style: _AppTypography.modelTitle(context),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Powered by ${model.baseModel ?? model.name} (${model.sizeMB >= 1024 ? '${(model.sizeMB / 1024).toStringAsFixed(1)} GB' : '${model.sizeMB} MB'})',
                                        style: _AppTypography.modelSubtitle(context),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? flux.textPrimary : flux.border,
                                      width: 1,
                                    ),
                                    color: isSelected ? flux.textPrimary : flux.surface,
                                  ),
                                  child: Center(
                                    child: isSelected
                                        ? Icon(Icons.check, size: 16, color: flux.background)
                                        : Icon(Icons.add, size: 16, color: flux.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        Positioned(
          right: 20,
          bottom: 40,
          child: BouncyFadeSlide(
            delay: const Duration(milliseconds: 200),
            duration: const Duration(milliseconds: 500),
            slideOffset: 20,
            child: _AnimatedButton(
              text: 'Next',
              onPressed: selectedModel != null ? onNext : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _FinishSlide extends StatelessWidget {
  final VoidCallback onFinish;

  const _FinishSlide({super.key, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        const spacing = 60.0;
        const contentHeight = 31.0 + spacing + 44;
        final topPadding = ((screenHeight - contentHeight) / 2) + 60;

        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: topPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BouncyFadeSlide(
                    delay: const Duration(milliseconds: 100),
                    duration: const Duration(milliseconds: 600),
                    slideOffset: 20,
                    child: Text(
                      AppLocalizations.of(context)!.thatsIt,
                      style: _AppTypography.heading(context),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: spacing),

                  BouncyFadeSlide(
                    delay: const Duration(milliseconds: 200),
                    duration: const Duration(milliseconds: 600),
                    slideOffset: 20,
                    child: _AnimatedButton(
                      text: AppLocalizations.of(context)!.finish,
                      onPressed: onFinish,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// COMPONENTS — v0.1.6 pill buttons, current animations
// ============================================================================

class _AnimatedButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const _AnimatedButton({required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    return BouncyTap(
      onTap: onPressed,
      scaleDown: 0.95,
      child: AnimatedContainer(
        duration: FluxDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: onPressed != null
              ? flux.textPrimary
              : flux.textPrimary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          text,
          style: _AppTypography.button(context),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    return BouncyTap(
      onTap: onPressed,
      scaleDown: 0.9,
      child: Container(
        padding: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(
              _AppAssets.backArrow,
              width: 10,
              height: 18,
              colorFilter: ColorFilter.mode(flux.textSecondary, BlendMode.srcIn),
            ),
            const SizedBox(width: 13),
            Text(
              AppLocalizations.of(context)!.back,
              style: _AppTypography.backButton(context),
            ),
          ],
        ),
      ),
    );
  }
}
