import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';

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
  int _lastEmittedLen = 0;

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

  /// Context size of the currently loaded model (estimated, fallback 2048).
  int get contextSize => _contextSize ?? 2048;
  int? _contextSize;

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

    final fileSizeMB = File(localPath).lengthSync() ~/ (1024 * 1024);
    final mmProjPath = localPath.replaceAll('.gguf', '.mmproj');
    final hasVision = File(mmProjPath).existsSync();

    final ctx = fileSizeMB < 1000 ? 8192 : 16384;

      _engine = LlamaEngine(LlamaBackend());

    await _engine!.loadModel(
      localPath,
      modelParams: ModelParams(
        contextSize: ctx,
        gpuLayers: 99,
        batchSize: 4096,
        microBatchSize: 2048,
      ),
    );

    if (hasVision) {
      await _engine!.loadMultimodalProjector(mmProjPath);
    }

    _loadedModelPath = localPath;
    _contextSize = ctx;
    return localPath;
  }

  /// Pre-warm the engine by loading the model in the background.
  /// Call this on app start so the first message is near-instant.
  Future<void> warmUp(String modelId) async {
    // Loads the last-used model in the background so it's ready.
    try {
      final directory = await getApplicationDocumentsDirectory();
      final modelPath = '${directory.path}/models/${modelId.replaceAll('/', '_')}.gguf';
      if (File(modelPath).existsSync()) {
        await loadModel(modelPath);
      }
    } catch (_) {
      // Silently ignore — inference will lazy-load if warmup fails
    }
  }
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
    List<String>? imagePaths,
    List<ToolDefinition>? tools,
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
          "You are Flux, an on-device AI. Answer concisely. Stop after answering.";
      messages.add(LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: effectiveSystem,
      ));

      int historyChars = 0;
      const int maxHistoryChars = 8000;
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

      if (imagePaths != null && imagePaths.isNotEmpty) {
        final parts = <LlamaContentPart>[
          LlamaTextContent(prompt),
          for (final path in imagePaths) LlamaImageContent(path: path),
        ];
        messages.add(LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: parts,
        ));
      } else {
        messages.add(LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: prompt,
        ));
      }

      final totalPromptChars = effectiveSystem.length + historyChars + prompt.length;
      final estimatedPromptTokens = (totalPromptChars / 3.5).round();

      const stopSequences = [
        "<|im_end|>",
        "<|endoftext|>",
      ];

      final baseParams = GenerationParams(
        temp: 0.0,
        maxTokens: maxTokens,
        stopSequences: stopSequences,
        streamBatchTokenThreshold: 4,
        streamBatchByteThreshold: 256,
        reusePromptPrefix: true,
        penalty: 1.0,
      );

      final stopwatch = Stopwatch()..start();
      int tokenCount = 0;
      bool firstTokenEmitted = false;

      const maxToolRounds = 20;

      for (int round = 0; round < maxToolRounds; round++) {
        final stream = _engine!.create(
          messages,
          params: baseParams,
          tools: tools,
        );

        List<LlamaCompletionChunkToolCall>? lastToolCalls;
        final contentBuf = StringBuffer();
        bool hasEmittedText = false;
        _lastEmittedLen = 0;

        await for (final chunk in stream) {
          for (final choice in chunk.choices) {
            if (choice.delta.content != null) {
              contentBuf.write(choice.delta.content!);
            }
            if (choice.delta.toolCalls != null &&
                choice.delta.toolCalls!.isNotEmpty) {
              lastToolCalls = choice.delta.toolCalls;
            }
          }

          // Only yield buffered text when we're confident
          // the model isn't about to emit a tool call. Wait until
          // we have enough buffer to detect tool-call patterns.
          if (!hasEmittedText || contentBuf.length > 80) {
            final cleaned = _stripToolCallText(contentBuf.toString());
            if (cleaned.isNotEmpty && !_looksLikeToolCallPrefix(cleaned)) {
              final start = _lastEmittedLen.clamp(0, cleaned.length);
              final toEmit =
                  hasEmittedText ? cleaned.substring(start) : cleaned;
              if (toEmit.isNotEmpty) {
                if (!firstTokenEmitted) {
                  final ttftMs = stopwatch.elapsedMilliseconds;
                  if (ttftMs > 0) {
                    _lastPromptTokPerSec =
                        estimatedPromptTokens / (ttftMs / 1000.0);
                  }
                  _lastPromptTokens = estimatedPromptTokens;
                  firstTokenEmitted = true;
                }
                tokenCount += (toEmit.length / 3.5).round();
                yield toEmit;
                hasEmittedText = true;
                _lastEmittedLen = cleaned.length;
              }
            }
          }
        }

        // Flush any remaining buffered text that isn't a tool call
        if (lastToolCalls == null || lastToolCalls.isEmpty) {
          final remaining =
              _stripToolCallText(contentBuf.toString());
          if (remaining.isNotEmpty) {
            if (hasEmittedText) {
              final start = _lastEmittedLen.clamp(0, remaining.length);
              final tail = remaining.substring(start);
              if (tail.isNotEmpty) {
                yield tail;
                tokenCount += (tail.length / 3.5).round();
              }
            } else {
              yield remaining;
              tokenCount += (remaining.length / 3.5).round();
            }
          }
        }

        if (lastToolCalls == null ||
            lastToolCalls.isEmpty ||
            tools == null ||
            tools.isEmpty) {
          break;
        }

        // Add assistant message with the tool calls
        messages.add(LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            for (final tc in lastToolCalls)
              LlamaToolCallContent(
                id: tc.id,
                name: tc.function?.name ?? 'unknown',
                arguments: tc.function?.arguments != null
                    ? jsonDecode(tc.function!.arguments!)
                        as Map<String, dynamic>
                    : {},
                rawJson: tc.function?.arguments ?? '{}',
              ),
          ],
        ));

        // Execute each tool call and add results
        for (final tc in lastToolCalls) {
          final toolName = tc.function?.name;
          final toolArgs = tc.function?.arguments;
          if (toolName == null || toolArgs == null) continue;

          final def = tools.firstWhere(
            (t) => t.name == toolName,
            orElse: () => throw Exception('Unknown tool: $toolName'),
          );

          try {
            final args = jsonDecode(toolArgs) as Map<String, dynamic>;
            final result = await def.invoke(args);
            messages.add(LlamaChatMessage.withContent(
              role: LlamaChatRole.tool,
              content: [
                LlamaToolResultContent(
                  id: tc.id,
                  name: toolName,
                  result: result,
                ),
              ],
            ));
          } catch (e) {
            messages.add(LlamaChatMessage.withContent(
              role: LlamaChatRole.tool,
              content: [
                LlamaToolResultContent(
                  id: tc.id,
                  name: toolName,
                  result: 'Error: $e',
                ),
              ],
            ));
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

  /// Remove raw tool-call JSON and markup that some models leak as text content.
  static String _stripToolCallText(String text) {
    return text
        .replaceAll(RegExp(r'<\s*/?\s*tool_call\s*>', caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'\{\s*"name"\s*:\s*"[^"]+"\s*,\s*"arguments"\s*:'
                r'\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*\}'),
            '')
        .trim();
  }

  /// Whether the text looks like it could be the start of a tool-call JSON
  /// that hasn't fully streamed yet.
  static bool _looksLikeToolCallPrefix(String text) {
    final trimmed = text.trim();
    return trimmed == '<tool_call>';
  }
}
