import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'l10n/app_localizations.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/chat/chat_screen.dart';
import 'features/creations/creations_screen.dart';
import 'features/creations/creation_editor_screen.dart';
import 'features/creations/creation_app_screen.dart';
import 'features/models/models_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/about_screen.dart';
import 'core/widgets/flux_shell.dart';
import 'core/theme/flux_theme.dart';
import 'core/widgets/flux_animations.dart';
import 'core/services/inference_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox('models'),
    Hive.openBox('settings'),
    Hive.openBox('chats'),
    Hive.openBox('creations'),
  ]);

  const token = String.fromEnvironment('HUGGINGFACE_TOKEN');
  FlutterGemma.initialize(
    huggingFaceToken: token.isEmpty ? null : token,
    maxDownloadRetries: 5,
  );

  final prefs = await SharedPreferences.getInstance();
  final onboarded = prefs.getBool('onboarded') ?? false;

  // Pre-warm the model on app start so the first message is near-instant.
  // This runs in the background and does not block the UI.
  if (onboarded) {
    final savedModelId = prefs.getString('selectedModelId');
    if (savedModelId != null && savedModelId.isNotEmpty) {
      unawaited(InferenceService().warmUp(savedModelId));
    }
  }

  // Desktop-aware system UI overlay
  final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  if (!isDesktop) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
  }

  runApp(ProviderScope(child: FluxApp(onboarded: onboarded)));
}

// Smooth, balanced page transition with parallax and delayed reveal
CustomTransitionPage buildSlidePage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 550),
    reverseTransitionDuration: const Duration(milliseconds: 550),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tabInfo = TabNavigationInfo.of(context);
      final location = state.location;
      final isShellSubRoute = location == '/home' || location == '/creations' || location == '/settings';
      final currentLocation = GoRouterState.of(context).location;
      final isCurrentShell = currentLocation == '/home' || currentLocation == '/creations' || currentLocation == '/settings';
      final isTabSwitch = isShellSubRoute && isCurrentShell && tabInfo != null && tabInfo.previousIndex != tabInfo.currentIndex;

      bool isForwardLayout = true;
      if (isTabSwitch) {
        isForwardLayout = tabInfo.currentIndex > tabInfo.previousIndex;
      }

      return FluxPageTransition(
        primaryAnimation: animation,
        secondaryAnimation: secondaryAnimation,
        isForwardLayout: isForwardLayout,
        child: child,
      );
    },
  );
}

class FluxApp extends StatefulWidget {
  final bool onboarded;
  const FluxApp({super.key, required this.onboarded});

  @override
  State<FluxApp> createState() => _FluxAppState();
}

class _FluxAppState extends State<FluxApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.onboarded ? '/home' : '/onboarding',
      routes: [
          GoRoute(
          path: '/onboarding',
          pageBuilder: (context, state) => buildSlidePage(
            state: state,
            child: const OnboardingScreen(),
          ),
        ),
        ShellRoute(
          builder: (context, state, child) => FluxShell(child: child),
          routes: [
            GoRoute(
              path: '/home',
              pageBuilder: (context, state) => buildSlidePage(
                state: state,
                child: const ChatScreen(),
              ),
            ),
            GoRoute(
              path: '/creations',
              pageBuilder: (context, state) => buildSlidePage(
                state: state,
                child: const CreationsScreen(),
              ),
            ),
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) => buildSlidePage(
                state: state,
                child: const SettingsScreen(),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/settings/models',
          pageBuilder: (context, state) => buildSlidePage(
            state: state,
            child: const ModelsScreen(),
          ),
        ),
        GoRoute(
          path: '/settings/about',
          pageBuilder: (context, state) => buildSlidePage(
            state: state,
            child: const AboutScreen(),
          ),
        ),
        GoRoute(
          path: '/model/:id',
          pageBuilder: (context, state) => buildSlidePage(
            state: state,
            child: ChatScreen(modelId: state.params['id']),
          ),
        ),
        GoRoute(
          path: '/creations/editor',
          pageBuilder: (context, state) {
            final id = (state.extra as String?) ?? state.queryParams['id'];
            return buildSlidePage(
              state: state,
              child: CreationEditorScreen(creationId: id),
            );
          },
        ),
        GoRoute(
          path: '/creations/app/:id',
          pageBuilder: (context, state) {
            final id = state.params['id']!;
            return buildSlidePage(
              state: state,
              child: CreationAppScreen(creationId: id),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Flux',
      debugShowCheckedModeBanner: false,
      theme: FluxTheme.light,
      darkTheme: FluxTheme.dark,
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}
