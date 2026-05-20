import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llamadart/llamadart.dart';
import '../services/search_service.dart';

class Skill {
  final String id;
  final String name;
  final String description;
  final bool isEnabled;
  final ToolDefinition? tool;

  Skill({
    required this.id,
    required this.name,
    required this.description,
    this.isEnabled = true,
    this.tool,
  });

  Skill copyWith({bool? isEnabled}) {
    return Skill(
      id: id,
      name: name,
      description: description,
      isEnabled: isEnabled ?? this.isEnabled,
      tool: tool,
    );
  }
}

class SkillNotifier extends StateNotifier<List<Skill>> {
  SkillNotifier() : super([
    Skill(
      id: 'web_search',
      name: 'Web Search',
      description: 'Allows Flux to search the web for real-time information.',
      tool: SearchService.webSearchTool,
    ),
    Skill(
      id: 'creations',
      name: 'Creations',
      description: 'Allows Flux to build interactive HTML applications.',
      // Tool logic for creations is handled specially in ChatScreen for now
    ),
  ]);

  void toggleSkill(String id) {
    state = [
      for (final skill in state)
        if (skill.id == id) skill.copyWith(isEnabled: !skill.isEnabled) else skill,
    ];
  }

  void addSkill(Skill skill) {
    state = [...state, skill];
  }

  List<ToolDefinition> getActiveTools() {
    return state
        .where((s) => s.isEnabled && s.tool != null)
        .map((s) => s.tool!)
        .toList();
  }
}

final skillProvider = StateNotifierProvider<SkillNotifier, List<Skill>>((ref) {
  return SkillNotifier();
});
