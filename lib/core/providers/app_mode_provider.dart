import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppMode { flux, fluxCode }

class AppModeNotifier extends StateNotifier<AppMode> {
  AppModeNotifier() : super(AppMode.flux) {
    _load();
  }

  static const _prefsKey = 'appMode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_prefsKey);
      if (modeStr == 'fluxCode') {
        state = AppMode.fluxCode;
      } else {
        state = AppMode.flux;
      }
    } catch (_) {}
  }

  Future<void> setMode(AppMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode == AppMode.fluxCode ? 'fluxCode' : 'flux');
    } catch (_) {}
  }
}

final appModeProvider = StateNotifierProvider<AppModeNotifier, AppMode>((ref) => AppModeNotifier());
