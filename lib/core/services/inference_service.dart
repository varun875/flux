import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:image/image.dart' as img;
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
  /// Vision models need a larger window because images are converted to
  /// many vision tokens at inference time.
  static int _maxTokensFor(String modelId) {
    if (ModelService.supportsVision(modelId)) return 8192;
    return 4096;
  }

  Future<InferenceModel> _loadModelWithBestBackend(String modelId) async {
    final fileType = _fileTypeFor(modelId);
    final maxTokens = _maxTokensFor(modelId);
    final supportsVision = ModelService.supportsVision(modelId);

    if (fileType == ModelFileType.litertlm) {
      try {
        return await FlutterGemma.getActiveModel(
          maxTokens: maxTokens,
          preferredBackend: PreferredBackend.gpu,
          supportImage: supportsVision,
          maxNumImages: supportsVision ? 1 : null,
        );
      } catch (_) {}
      return await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: PreferredBackend.cpu,
        supportImage: supportsVision,
        maxNumImages: supportsVision ? 1 : null,
      );
    }

    final modelType = _modelTypeFor(modelId);
    try {
      return await FlutterGemmaPlugin.instance.createModel(
        modelType: modelType,
        fileType: fileType,
        maxTokens: maxTokens,
        preferredBackend: PreferredBackend.npu,
        supportImage: supportsVision,
        maxNumImages: supportsVision ? 1 : null,
      );
    } catch (_) {}

    return await FlutterGemmaPlugin.instance.createModel(
      modelType: modelType,
      fileType: fileType,
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.gpu,
      supportImage: supportsVision,
      maxNumImages: supportsVision ? 1 : null,
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
    } catch (_) {
    } finally {
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
    } catch (_) {
    } finally {
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

  static Uint8List _resizeJpegInIsolate(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    const maxEdge = 768;
    final needsResize = decoded.width > maxEdge || decoded.height > maxEdge;
    final resized = needsResize
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxEdge : null,
            height: decoded.height > decoded.width ? maxEdge : null,
            interpolation: img.Interpolation.linear,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  Future<Uint8List?> _readFirstImage(List<String> imagePaths) async {
    for (final path in imagePaths) {
      if (path.isEmpty) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      return _stageImageForInference(bytes);
    }
    return null;
  }

  /// Decode, downscale, and re-encode the picked image as a smaller JPEG so it
  /// fits comfortably in the vision model's context window. image_picker's
  /// maxWidth/maxHeight/imageQuality options are silently ignored on Windows,
  /// so we normalise here regardless of platform.
  Future<Uint8List?> _stageImageForInference(Uint8List bytes) async {
    try {
      return await compute(_resizeJpegInIsolate, bytes);
    } catch (_) {
      return bytes;
    }
  }

  Stream<String> streamChat({
    required String modelId,
    required String prompt,
    String? conversationId,
    String? localPath,
    String? systemPrompt,
    List<String> imagePaths = const [],
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

      final supportsVision = ModelService.supportsVision(modelId);
      final imageBytes =
          imagePaths.isNotEmpty ? await _readFirstImage(imagePaths) : null;

      if (imagePaths.isNotEmpty && !supportsVision) {
        yield "Error: The selected model does not support image input. Choose Flux Steady or Flux Smart.";
        return;
      }

      if (imagePaths.isNotEmpty && imageBytes == null) {
        yield "Error: Could not read the selected image. Please pick it again.";
        return;
      }

      if (!sameChat) {
        final effectiveSystem = systemPrompt ??
            "You are Flux, an on-device AI assistant. Answer concisely and accurately.";

        _chat = await _activeModel!.createChat(
          systemInstruction: effectiveSystem,
          modelType: _modelTypeFor(modelId),
          temperature: 0.7,
          tokenBuffer: 256,
          supportImage: supportsVision,
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

      await _chat!.addQueryChunk(
        imageBytes != null
            ? Message.withImage(
                text: prompt, imageBytes: imageBytes, isUser: true)
            : Message.text(text: prompt, isUser: true),
      );

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
