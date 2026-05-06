import 'dart:async';
import 'dart:io';
import 'package:llamadart/llamadart.dart';

class InferenceService {
  static final InferenceService _instance = InferenceService._internal();
  factory InferenceService() => _instance;
  InferenceService._internal() {
    LlamaEngine.configureLogging(level: LlamaLogLevel.none);
  }

  LlamaEngine? _engine;
  String? _loadedModelPath;

  double _lastPromptTokPerSec = 0;
  double _lastOutputTokPerSec = 0;
  int _lastPromptTokens = 0;
  int _lastOutputTokens = 0;

  double get lastPromptTokPerSec => _lastPromptTokPerSec;
  double get lastOutputTokPerSec => _lastOutputTokPerSec;
  int get lastPromptTokens => _lastPromptTokens;
  int get lastOutputTokens => _lastOutputTokens;

  /// Whether a model is currently loaded and ready.
  bool get isLoaded => _engine != null && _loadedModelPath != null;

  /// The name of the currently loaded model (e.g. "flux-lite-qwen-3.5-0.8b").
  String? get modelName =>
      _loadedModelPath?.split('/').last.replaceAll('.gguf', '');

  /// The full file path to the currently loaded model.
  String? get modelPath => _loadedModelPath;

  /// Load a model into the engine. If a different model is already loaded,
  /// the old one is disposed first. Returns the path on success, or throws
  /// on failure. Safe to call multiple times with the same path (no-op).
  Future<String> loadModel(String localPath) async {
    if (!File(localPath).existsSync()) {
      throw Exception('Model file not found: $localPath');
    }

    if (_loadedModelPath == localPath && _engine != null) {
      return localPath; // already loaded
    }

    if (_engine != null) {
      await _engine!.dispose();
      _engine = null;
    }

    _engine = LlamaEngine(LlamaBackend());

    await     _engine!.loadModel(
      localPath,
      modelParams: const ModelParams(
        contextSize: 8192,
        gpuLayers: 99,
        batchSize: 1024,
        microBatchSize: 512,
      ),
    );

    // Auto-detect and load multimodal projector (mmproj) for vision models
    final mmProjPath = localPath.replaceAll('.gguf', '.mmproj');
    if (File(mmProjPath).existsSync()) {
      await _engine!.loadMultimodalProjector(mmProjPath);
    }

    _loadedModelPath = localPath;
    return localPath;
  }

  /// Unload the current model (discard engine resources).
  Future<void> unloadModel() async {
    if (_engine != null) {
      await _engine!.dispose();
      _engine = null;
    }
    _loadedModelPath = null;
  }

  Stream<String> streamChat({
    required String modelId,
    required String prompt,
    String? localPath,
    String? systemPrompt,
    List<Map<String, String>> history = const [],
    int maxTokens = 8192,
  }) async* {
    if (localPath == null || !File(localPath).existsSync()) {
      yield "Error: Local model file not found at $localPath.";
      return;
    }

    try {
      if (_loadedModelPath != localPath) {
        await loadModel(localPath);
      }

      if (_engine == null) {
        yield "Error: Failed to load model engine.";
        return;
      }

      final messages = <LlamaChatMessage>[];

      final effectiveSystem = systemPrompt ??
          "You are Flux, an on-device AI. "
          "IMPORTANT: You have perfect memory of this conversation. "
          "The full conversation history is provided to you with every message, "
          "so you can reference anything said earlier. "
          "Never claim you do not remember something from this chat — you do. "
          "Answer concisely and accurately. Never hallucinate other conversations or users. "
          "Stop immediately after answering.";
      messages.add(LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: effectiveSystem,
      ));

      int historyChars = 0;
      const int maxHistoryChars = 6000;
      for (final turn in history) {
        final role = turn['role'] ?? 'user';
        final content = turn['content'] ?? '';
        historyChars += content.length;
        if (historyChars > maxHistoryChars) break;
        messages.add(LlamaChatMessage.fromText(
          role: role == 'assistant'
              ? LlamaChatRole.assistant
              : LlamaChatRole.user,
          text: content,
        ));
      }

      messages.add(LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: prompt,
      ));

      final totalPromptChars = effectiveSystem.length + historyChars + prompt.length;
      final estimatedPromptTokens = (totalPromptChars / 3.5).round();

      const stopSequences = [
        "<|im_end|>",
        "<|endoftext|>",
      ];

      final stream = _engine!.create(
        messages,
        params: GenerationParams(
          temp: 0.0,
          maxTokens: maxTokens,
          stopSequences: stopSequences,
        ),
      );

      final stopwatch = Stopwatch()..start();
      int tokenCount = 0;
      int ttftMs = 0;

      await for (final chunk in stream) {
        for (final choice in chunk.choices) {
          if (choice.delta.content != null) {
            if (tokenCount == 0) {
              ttftMs = stopwatch.elapsedMilliseconds;
              if (ttftMs > 0) {
                _lastPromptTokPerSec = estimatedPromptTokens / (ttftMs / 1000.0);
              }
              _lastPromptTokens = estimatedPromptTokens;
            }
            tokenCount++;
            yield choice.delta.content!;
          }
        }
      }

      final elapsedMs = stopwatch.elapsedMilliseconds;
      if (elapsedMs > 0 && tokenCount > 0) {
        _lastOutputTokPerSec = tokenCount / (elapsedMs / 1000.0);
        _lastOutputTokens = tokenCount;
      }
    } catch (e) {
      yield "Error: ${e.toString()}";
    }
  }
}
