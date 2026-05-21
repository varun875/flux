import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/flux_code_project.dart';

/// Persisted list of Flux Code projects.
class FluxCodeProjectsNotifier extends StateNotifier<List<FluxCodeProject>> {
  FluxCodeProjectsNotifier() : super([]) {
    _load();
  }

  static const _boxName = 'flux_code_projects';

  Box get _box => Hive.box(_boxName);

  void _load() {
    if (!Hive.isBoxOpen(_boxName)) return;
    final items = _box.values
        .map((v) => FluxCodeProject.fromJson(Map<String, dynamic>.from(v)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    state = items;
  }

  Future<FluxCodeProject> addProject({
    required String name,
    required String path,
  }) async {
    final p = FluxCodeProject(
      id: const Uuid().v4(),
      name: name,
      path: path,
      createdAt: DateTime.now(),
    );
    await _box.put(p.id, p.toJson());
    state = [p, ...state];
    return p;
  }

  Future<void> rename(String id, String newName) async {
    final idx = state.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final updated = state[idx].copyWith(name: newName);
    await _box.put(id, updated.toJson());
    state = [
      for (final p in state) p.id == id ? updated : p,
    ];
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
    state = state.where((p) => p.id != id).toList();
  }
}

final fluxCodeProjectsProvider = StateNotifierProvider<
    FluxCodeProjectsNotifier, List<FluxCodeProject>>(
  (ref) => FluxCodeProjectsNotifier(),
);

/// Currently active project (the agent's working directory). Null means
/// the agent has no project context and can only do general coding Q&A.
final activeFluxCodeProjectIdProvider = StateProvider<String?>((ref) => null);

final activeFluxCodeProjectProvider = Provider<FluxCodeProject?>((ref) {
  final id = ref.watch(activeFluxCodeProjectIdProvider);
  if (id == null) return null;
  final projects = ref.watch(fluxCodeProjectsProvider);
  for (final p in projects) {
    if (p.id == id) return p;
  }
  return null;
});
