import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/hf_model.dart';
import '../services/inference_service.dart';

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, List<HFModel>>((ref) {
  return DownloadNotifier();
});

class DownloadNotifier extends StateNotifier<List<HFModel>> {
  final Map<String, CancelToken> _cancelTokens = {};

  DownloadNotifier() : super([]) {
    _loadInstalledModels();
  }

  @override
  void dispose() {
    for (final token in _cancelTokens.values) {
      token.cancel('Provider disposed');
    }
    _cancelTokens.clear();
    super.dispose();
  }

  void _loadInstalledModels() {
    final box = Hive.box('models');
    final installed = box.values
        .map((v) => HFModel.fromJson(Map<String, dynamic>.from(v)))
        .toList();
    final existingIds = state.map((m) => m.id).toSet();
    final newModels = installed.where((m) => !existingIds.contains(m.id)).toList();
    state = [...state, ...newModels];
  }

  Future<void> startDownloadWithUrl(HFModel model, String url) async {
    if (url.isEmpty) {
      debugPrint('Could not find download URL for ${model.id}');
      return;
    }

    // Cancel any existing download for this model
    _cancelTokens[model.id]?.cancel('Replaced by new download');

    final cancelToken = CancelToken();
    _cancelTokens[model.id] = cancelToken;

    // Preserve existing progress if resuming, otherwise start at 0
    final currentProgress = model.progress;
    final updatedModel = model.copyWith(
      downloadStatus: 'downloading',
      progress: currentProgress,
    );

    if (state.any((m) => m.id == model.id)) {
      state = state.map((m) => m.id == model.id ? updatedModel : m).toList();
    } else {
      state = [...state, updatedModel];
    }

    // Determine ModelType from the model definition
    ModelType modelType;
    switch (model.modelType) {
      case 'gemma4':
        modelType = ModelType.gemma4;
        break;
      default:
        modelType = ModelType.gemmaIt;
    }

    // Determine ModelFileType
    ModelFileType fileType;
    switch (model.fileType) {
      case 'litertlm':
        fileType = ModelFileType.litertlm;
        break;
      case 'binary':
        fileType = ModelFileType.binary;
        break;
      default:
        fileType = ModelFileType.task;
    }

    try {
      await FlutterGemma.installModel(
        modelType: modelType,
        fileType: fileType,
      ).fromNetwork(url).withCancelToken(cancelToken).withProgress((progress) {
        if (!mounted) return;
        state = state.map((m) {
          if (m.id == model.id) {
            return m.copyWith(
              downloadStatus: 'downloading',
              progress: progress,
            );
          }
          return m;
        }).toList();
      }).install();

      if (!mounted) return;
      _markAsCompleted(model.id);

      // Preload the model in the background so the first message is fast.
      unawaited(InferenceService().preloadModel(model.id));
    } catch (e) {
      if (CancelToken.isCancel(e)) {
        return;
      }
      if (!mounted) return;
      debugPrint('Download failed for ${model.id}: $e');
      _markAsFailed(model.id, e.toString());
    } finally {
      _cancelTokens.remove(model.id);
    }
  }

  void _markAsCompleted(String id) {
    final matches = state.where((m) => m.id == id);
    if (matches.isEmpty) return;
    final model = matches.first;

    final completedModel = model.copyWith(
      downloaded: true,
      progress: 100,
      downloadStatus: 'completed',
    );

    state = state.map((m) => m.id == id ? completedModel : m).toList();

    final box = Hive.box('models');
    box.put(id, completedModel.toJson());
  }

  void _markAsFailed(String id, [String? error]) {
    state = state.map((m) {
      if (m.id == id) {
        return m.copyWith(
          downloadStatus: 'none',
          progress: 0,
          errorMessage: error,
        );
      }
      return m;
    }).toList();
  }

  Future<void> deleteModel(String id) async {
    final modelIndex = state.indexWhere((m) => m.id == id);
    if (modelIndex == -1) return;

    final box = Hive.box('models');
    await box.delete(id);

    // Reset download state but keep the model in the library
    state = state
        .map((m) => m.id == id
            ? m.copyWith(
                downloadStatus: 'none',
                downloaded: false,
                localPath: null,
                progress: 0,
              )
            : m)
        .toList();
  }

  /// Cancel a downloading model
  Future<void> cancelDownload(String id) async {
    // Cancel the download via CancelToken
    _cancelTokens[id]?.cancel('User cancelled download');
    _cancelTokens.remove(id);

    // Reset state
    state = state.map((m) {
      if (m.id == id) {
        return m.copyWith(
          downloadStatus: 'none',
          progress: 0,
          downloadSpeed: 0,
        );
      }
      return m;
    }).toList();
  }
}
