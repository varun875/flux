import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'model_service.dart';

class InferenceService {
  static final InferenceService _instance = InferenceService._internal();
  factory InferenceService() => _instance;
  InferenceService._internal();

  InferenceModel? _activeModel;
  String? _loadedModelId;
  InferenceChat? _chat;
  String? _chatModelId;
  String? _chatConversationId;
  bool _isPreloading = false;

  /// Models for which installModel() has been called in this session.
  final Set<String> _registeredModelIds = {};

  /// Serializes model loads so warmUp + streamChat don't race.
  Future<void>? _loadingFuture;

  double _lastPromptTokPerSec = 0;
  double _lastOutputTokPerSec = 0;
  int _lastPromptTokens = 0;
  int _lastOutputTokens = 0;

  double get lastPromptTokPerSec => _lastPromptTokPerSec;
  double get lastOutputTokPerSec => _lastOutputTokPerSec;
  int get lastPromptTokens => _lastPromptTokens;
  int get lastOutputTokens => _lastOutputTokens;

  bool get isLoaded => _activeModel != null && _loadedModelId != null;

  String? get modelName => _loadedModelId;

  String? get modelPath => _loadedModelId;

  static ModelType _modelTypeFor(String modelId) {
    return ModelType.gemma4;
  }

  static ModelFileType _fileTypeFor(String modelId) {
    return ModelFileType.litertlm;
  }

  /// Returns the optimal maxTokens (context length) for a given model.
  static int _maxTokensFor(String modelId) {
    return 4096;
  }

  Future<InferenceModel> _loadModelWithBestBackend(String modelId) async {
    final fileType = _fileTypeFor(modelId);
    final maxTokens = _maxTokensFor(modelId);

    if (fileType == ModelFileType.litertlm) {
      try {
        return await FlutterGemma.getActiveModel(
          maxTokens: maxTokens,
          preferredBackend: PreferredBackend.gpu,
        );
      } catch (_) {}
      return await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: PreferredBackend.cpu,
      );
    }

    final modelType = _modelTypeFor(modelId);
    try {
      return await FlutterGemmaPlugin.instance.createModel(
        modelType: modelType,
        fileType: fileType,
        maxTokens: maxTokens,
        preferredBackend: PreferredBackend.npu,
      );
    } catch (_) {}

    return await FlutterGemmaPlugin.instance.createModel(
      modelType: modelType,
      fileType: fileType,
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.gpu,
    );
  }

  /// Register the model with flutter_gemma and load it into memory.
  /// Guarded against concurrent loads — second caller awaits the first.
  Future<void> _ensureModel(String modelId) async {
    if (_loadedModelId == modelId && _activeModel != null) return;

    // If another load is in progress, wait and re-check.
    if (_loadingFuture != null) {
      await _loadingFuture;
      if (_loadedModelId == modelId && _activeModel != null) return;
    }

    final completer = Completer<void>();
    _loadingFuture = completer.future;

    try {
      if (!_registeredModelIds.contains(modelId)) {
        final url = ModelService.getDownloadUrl(modelId);
        if (url.isNotEmpty) {
          try {
            await FlutterGemma.installModel(
              modelType: _modelTypeFor(modelId),
              fileType: _fileTypeFor(modelId),
            ).fromNetwork(url).install();
            _registeredModelIds.add(modelId);
          } catch (_) {}
        }
      }

      if (_activeModel != null) {
        await _activeModel!.close();
        _activeModel = null;
      }

      _activeModel = await _loadModelWithBestBackend(modelId);
      _loadedModelId = modelId;
      _chat = null;
      _chatModelId = null;
      _chatConversationId = null;
      _lastPromptTokPerSec = 0;
      _lastOutputTokPerSec = 0;
      _lastPromptTokens = 0;
      _lastOutputTokens = 0;
    } finally {
      _loadingFuture = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> preloadModel(String modelId) async {
    if (_isPreloading) return;
    if (modelId.isEmpty) return;
    if (_loadedModelId == modelId && _activeModel != null) return;

    _isPreloading = true;
    try {
      await _ensureModel(modelId);
      if (kDebugMode) debugPrint('Flux: preloaded $modelId');
    } catch (_) {} finally {
      _isPreloading = false;
    }
  }

  /// Warm the model into memory. First call per session registers via
  /// installModel(); subsequent messages find it already loaded.
  Future<void> warmUp(String modelId) async {
    if (_loadedModelId == modelId && _activeModel != null) return;
    if (_isPreloading) return;

    _isPreloading = true;
    try {
      await _ensureModel(modelId);
    } catch (_) {} finally {
      _isPreloading = false;
    }
  }

  void resetChat() {
    _chat = null;
    _chatModelId = null;
    _chatConversationId = null;
  }

  Future<void> unloadModel() async {
    _chat = null;
    _chatModelId = null;
    _chatConversationId = null;
    if (_activeModel != null) {
      await _activeModel!.close();
      _activeModel = null;
    }
    _loadedModelId = null;
  }

  Future<void> cancelGeneration() async {}

  Stream<String> streamChat({
    required String modelId,
    required String prompt,
    String? conversationId,
    String? localPath,
    String? systemPrompt,
    List<Map<String, String>> history = const [],
  }) async* {
    try {
      await _ensureModel(modelId);

      if (_activeModel == null) {
        yield "Error: No model is loaded. Please download a model first.";
        return;
      }

      final sameChat = _chat != null &&
          _chatModelId == modelId &&
          conversationId != null &&
          _chatConversationId == conversationId;

      if (!sameChat) {
        final effectiveSystem = systemPrompt ??
            "You are Flux, an on-device AI assistant. Answer concisely and accurately.";

        _chat = await _activeModel!.createChat(
          systemInstruction: effectiveSystem,
          modelType: _modelTypeFor(modelId),
          temperature: 0.7,
          tokenBuffer: 256,
        );
        _chatModelId = modelId;
        _chatConversationId = conversationId;

        int historyChars = 0;
        const int maxHistoryChars = 4000;
        for (final turn in history) {
          final content = turn['content'] ?? '';
          historyChars += content.length;
          if (historyChars > maxHistoryChars) break;
          await _chat!.addQueryChunk(Message.text(
            text: content,
            isUser: turn['role'] == 'user',
          ));
        }
      }

      await _chat!.addQueryChunk(Message.text(text: prompt, isUser: true));

      final estimatedPromptTokens = (prompt.length / 3.5).round();

      final stopwatch = Stopwatch()..start();
      int tokenCount = 0;
      int ttftMs = 0;

      final responseStream = _chat!.generateChatResponseAsync();

      await for (final response in responseStream) {
        if (response is TextResponse) {
          if (tokenCount == 0) {
            ttftMs = stopwatch.elapsedMilliseconds;
            if (ttftMs > 0) {
              _lastPromptTokPerSec = estimatedPromptTokens / (ttftMs / 1000.0);
            }
            _lastPromptTokens = estimatedPromptTokens;
          }
          tokenCount++;
          yield response.token;
        }
      }

      final elapsedMs = stopwatch.elapsedMilliseconds;
      if (elapsedMs > 0 && tokenCount > 0) {
        _lastOutputTokPerSec = tokenCount / (elapsedMs / 1000.0);
        _lastOutputTokens = tokenCount;
      }
    } catch (e) {
      _chat = null;
      _chatModelId = null;
      _chatConversationId = null;
      yield "Error: ${e.toString()}";
    }
  }

  Future<String> oneshotChat({
    required String modelId,
    required String prompt,
    String? systemPrompt,
    List<Map<String, String>> history = const [],
    int maxTokens = 256,
  }) async {
    await _ensureModel(modelId);
    if (_activeModel == null) return '';

    final effectiveSystem = systemPrompt ??
        "You are Flux, an on-device AI assistant. Answer concisely and accurately.";

    final chat = await _activeModel!.createChat(
      systemInstruction: effectiveSystem,
      modelType: _modelTypeFor(modelId),
      temperature: 0.7,
      tokenBuffer: 256,
    );

    for (final turn in history) {
      await chat.addQueryChunk(Message.text(
        text: turn['content'] ?? '',
        isUser: turn['role'] == 'user',
      ));
    }

    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

    final response = await chat.generateChatResponse();

    if (response is TextResponse) return response.token;
    return '';
  }
}
