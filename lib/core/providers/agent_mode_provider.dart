import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/code_agent_service.dart';

enum FluxAgentMode { assistant, codeAgent }

class AgentModeNotifier extends StateNotifier<FluxAgentMode> {
  AgentModeNotifier() : super(FluxAgentMode.assistant) {
    _load();
  }

  static const _prefsKey = 'desktopCodeAgentEnabled';

  Future<void> _load() async {
    if (!CodeAgentService.isComputerPlatform) {
      state = FluxAgentMode.assistant;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsKey) ?? false;
    state = enabled ? FluxAgentMode.codeAgent : FluxAgentMode.assistant;
  }

  Future<void> setMode(FluxAgentMode mode) async {
    if (!CodeAgentService.isComputerPlatform) return;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, mode == FluxAgentMode.codeAgent);
  }
}

final agentModeProvider =
    StateNotifierProvider<AgentModeNotifier, FluxAgentMode>(
  (ref) => AgentModeNotifier(),
);
