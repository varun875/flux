import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/inference_service.dart';
import '../../core/providers/download_provider.dart';
import '../../core/models/hf_model.dart';
import '../../core/theme/flux_theme.dart';
import '../../core/widgets/flux_widgets.dart';
import '../../core/widgets/flux_animations.dart';
import '../../core/constants/responsive.dart';
import '../../l10n/app_localizations.dart';
import 'creations_screen.dart';

// ============================================================================
// EDITOR SCREEN
// ============================================================================
class CreationEditorScreen extends ConsumerStatefulWidget {
  final String? creationId;
  const CreationEditorScreen({super.key, this.creationId});

  @override
  ConsumerState<CreationEditorScreen> createState() => _CreationEditorScreenState();
}

class _CreationEditorScreenState extends ConsumerState<CreationEditorScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  double _topFadeOpacity = 0.0;
  double _bottomFadeOpacity = 0.0;
  bool _isStreaming = false;
  bool _hasText = false;
  String? _latestHtml;
  bool _isPreviewOpen = false;
  DateTime? _lastSendTime;

  // Local message state for performance
  final List<_EditorMessage> _messages = [];
  final _streamingTextNotifier = ValueNotifier<String>('');
  WebViewController? _webViewController;

  // Adaptive token buffering: flush to the notifier on a shorter timer
  final StringBuffer _streamBuffer = StringBuffer();
  bool _shouldStop = false;
  bool _showTokenSpeed = false;
  Timer? _flushTimer;

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_streamBuffer.isNotEmpty) {
        _streamingTextNotifier.value = _streamBuffer.toString();
      }
    });
  }

  void _stopFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_streamBuffer.isNotEmpty) {
      _streamingTextNotifier.value = _streamBuffer.toString();
    }
  }

  void _stopGeneration() {
    _shouldStop = true;
    _stopFlushTimer();
    if (mounted) setState(() => _isStreaming = false);
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
    _loadCreation();
    _loadTokenSpeedPref();
    _scrollController.addListener(_onEditorScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkEditorBottomFade();
    });
  }

  void _onEditorScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final top = offset > 0 ? 1.0 : 0.0;
    final bottom = maxExtent > 0 && offset < maxExtent ? 1.0 : 0.0;
    if (top != _topFadeOpacity || bottom != _bottomFadeOpacity) {
      setState(() {
        _topFadeOpacity = top;
        _bottomFadeOpacity = bottom;
      });
    }
  }

  void _checkEditorBottomFade() {
    if (_scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) {
      setState(() => _bottomFadeOpacity = 1.0);
    }
  }

  void _loadTokenSpeedPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _showTokenSpeed = prefs.getBool('showTokenSpeed') ?? false);
  }

  void _loadCreation() {
    if (widget.creationId == null) return;
    final creations = ref.read(creationsProvider);
    final match = creations.where((c) => c.id == widget.creationId);
    if (match.isEmpty) return;
    final creation = match.first;
    setState(() {
      _latestHtml = creation.html;
      _messages.addAll(
        creation.messages.map((m) => _EditorMessage(
          text: m['text'] as String? ?? '',
          fromUser: m['role'] == 'user',
          time: DateTime.now(),
        )),
      );
    });
  }

  /// Heuristic: response looks cut-off if it doesn't end with a terminal
  /// punctuation, a closing tag, or a code-block fence.
  bool _looksTruncated(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.endsWith(',') || trimmed.endsWith(':') || trimmed.endsWith(';')) return true;
    if (trimmed.endsWith('-') || trimmed.endsWith('\u2014')) return true;
    if (trimmed.contains('```') && trimmed.split('```').length.isEven) return true;
    return false;
  }

  Future<String> _generateWithModel({
    required String prompt,
    required HFModel model,
    required List<Map<String, String>> history,
    required String systemPrompt,
    required StringBuffer buffer,
  }) async {
    final stream = InferenceService().streamChat(
      modelId: model.id,
      prompt: prompt,
      systemPrompt: systemPrompt,
      history: history,
    );

    await for (final token in stream) {
      if (!mounted || _shouldStop) break;
      buffer.write(token);
    }
    return buffer.toString();
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isStreaming) return;

    // Debounce: prevent double-sends within 500ms
    final now = DateTime.now();
    if (_lastSendTime != null && now.difference(_lastSendTime!).inMilliseconds < 500) {
      return;
    }
    _lastSendTime = now;

    HapticFeedback.lightImpact();
    setState(() {
      _messages.add(_EditorMessage(text: text, fromUser: true, time: DateTime.now()));
    });
    _controller.clear();
    _focusNode.unfocus();
    _scrollToBottom(smooth: false);

    // Use any downloaded model for creations
    final downloaded = ref.read(downloadProvider);
    final creativeModels = downloaded.where((m) => m.downloaded);
    final creativeModel = creativeModels.isNotEmpty ? creativeModels.first : null;

    if (creativeModel == null) {
      setState(() {
        _messages.add(_EditorMessage(
          text: 'No model is installed. Please download a model from the Models tab to use Creations.',
          fromUser: false,
          time: DateTime.now(),
        ));
      });
      return;
    }

    setState(() => _isStreaming = true);
    _shouldStop = false;
    _streamBuffer.clear();
    _streamingTextNotifier.value = '';
    _startFlushTimer();

    // Build history
    final history = <Map<String, String>>[];
    for (final msg in _messages) {
      if (msg.fromUser) {
        history.add({'role': 'user', 'content': msg.text});
      } else if (msg.text.isNotEmpty) {
        history.add({'role': 'assistant', 'content': msg.text});
      }
    }

    final systemPrompt = "You are Flux Creator. The user wants to build simple interactive HTML mini-apps. "
        "Always respond with a complete, self-contained HTML file inside a markdown code block (```html ... ```). "
        "Use inline CSS and JavaScript. Make it visually polished and interactive. "
        "If the user asks to refine or change something, output the full updated HTML again.";

    // First generation pass
    String accumulated = await _generateWithModel(
      prompt: text,
      model: creativeModel,
      history: history,
      systemPrompt: systemPrompt,
      buffer: _streamBuffer,
    );

    if (mounted && !_shouldStop && _looksTruncated(accumulated)) {
      _streamBuffer.clear();
      _streamingTextNotifier.value = accumulated;

      final contHistory = <Map<String, String>>[
        ...history,
        {'role': 'assistant', 'content': accumulated},
      ];

      final cont = await _generateWithModel(
        prompt: 'Continue from where you left off. Do not repeat anything.',
        model: creativeModel,
        history: contHistory,
        systemPrompt: systemPrompt,
        buffer: _streamBuffer,
      );

      if (cont.trim().isNotEmpty) {
        accumulated += cont;
      }
    }

    _stopFlushTimer();

    if (mounted && !_shouldStop) {
      _streamingTextNotifier.value = accumulated;
      final html = _extractHtml(accumulated);
      setState(() {
        _isStreaming = false;
        _messages.add(_EditorMessage(
          text: accumulated,
          fromUser: false,
          time: DateTime.now(),
          outputTokPerSec: InferenceService().lastOutputTokPerSec,
          outputTokens: InferenceService().lastOutputTokens,
        ));
        if (html != null && html.isNotEmpty) _latestHtml = html;
      });
      HapticFeedback.selectionClick();

      // Save creation
      final title = _messages.firstWhere((m) => m.fromUser, orElse: () => _messages.first).text;
      final creation = Creation(
        id: widget.creationId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: title.length > 40 ? '${title.substring(0, 40)}...' : title,
        html: _latestHtml ?? html ?? '',
        createdAt: widget.creationId != null
            ? ref.read(creationsProvider).firstWhere((c) => c.id == widget.creationId).createdAt
            : DateTime.now(),
        updatedAt: DateTime.now(),
        messages: _messages.map((m) => {'role': m.fromUser ? 'user' : 'assistant', 'text': m.text}).toList(),
      );
      await ref.read(creationsProvider.notifier).saveCreation(creation);

      if (!mounted) return;
      if (html != null && html.isNotEmpty && !_isPreviewOpen) {
        _showPreview(context);
      }
    }
  }

  String? _extractHtml(String text) {
    final htmlRegex = RegExp(r'```html\s*([\s\S]*?)\s*```', caseSensitive: false);
    var match = htmlRegex.firstMatch(text);
    if (match != null) return match.group(1)?.trim();

    final codeRegex = RegExp(r'```\s*([\s\S]*?)\s*```');
    match = codeRegex.firstMatch(text);
    if (match != null) {
      final content = match.group(1)?.trim() ?? '';
      if (content.toLowerCase().contains('<!doctype html>') ||
          content.toLowerCase().contains('<html') ||
          content.toLowerCase().contains('<body')) {
        return content;
      }
    }
    return null;
  }

  String? _extractExplanation(String text) {
    final codeRegex = RegExp(r'```');
    final match = codeRegex.firstMatch(text);
    if (match == null) return null;
    final before = text.substring(0, match.start).trim();
    return before.isNotEmpty ? before : null;
  }

  void _scrollToBottom({bool smooth = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        if (smooth) {
          _scrollController.animateTo(maxExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeInOutCubic);
        } else {
          _scrollController.jumpTo(maxExtent);
        }
      }
    });
  }

  void _showPreview(BuildContext context) {
    if (_latestHtml == null || _latestHtml!.isEmpty) return;
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    setState(() => _isPreviewOpen = true);

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(flux.background)
      ..loadHtmlString(_latestHtml!);

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (ctx) => _PreviewScreen(
          webViewController: _webViewController!,
          onClose: () {
            setState(() => _isPreviewOpen = false);
            Navigator.pop(ctx);
          },
        ),
      ),
    ).then((_) => mounted ? setState(() => _isPreviewOpen = false) : null);
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.removeListener(_onEditorScroll);
    _scrollController.dispose();
    _streamingTextNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final topPadding = mediaQuery.padding.top;
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final inputBottom = keyboardHeight > 0
        ? keyboardHeight + 16
        : (context.isDesktop ? 24.0 : MediaQuery.of(context).padding.bottom + 84.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: brightness == Brightness.dark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: flux.background,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              // Back button
              Positioned(
                left: 20,
                top: topPadding + 48,
                child: FluxBackButton(onTap: () => context.pop()),
              ),

              // Title
              Positioned(
                left: 20,
                top: topPadding + 100,
                child: FluxTitle(title: AppLocalizations.of(context)!.newChat),
              ),

              // Messages & Input
              Positioned(
                left: 20,
                right: 20,
                top: topPadding + 160,
                bottom: inputBottom,
                child: Column(
                  children: [
                    Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                          Positioned.fill(
                            child: _messages.isEmpty
                                ? _buildEmptyState(context, flux)
                                : ListView.builder(
                                    controller: _scrollController,
                                    padding: EdgeInsets.zero,
                                    itemCount: _messages.length + (_isStreaming ? 1 : 0),
                                    cacheExtent: 300,
                                    addAutomaticKeepAlives: false,
                                    addRepaintBoundaries: true,
                                    itemBuilder: (context, index) {
                                      if (index == _messages.length) {
                                        return _buildStreamingBubble(flux, true);
                                      }
                                      final msg = _messages[index];
                                      final isLast = index == _messages.length - 1 && !_isStreaming;
                                      return _buildBubble(msg, flux, isLast: isLast);
                                    },
                                  ),
                          ),
                          if (_topFadeOpacity > 0)
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 30,
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        flux.background,
                                        flux.background,
                                        flux.background.withValues(alpha: 0),
                                      ],
                                      stops: const [0.0, 0.3, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_bottomFadeOpacity > 0)
                            Positioned(
                              bottom: -5,
                              left: 0,
                              right: 0,
                              height: 30,
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        flux.background,
                                        flux.background,
                                        flux.background.withValues(alpha: 0),
                                      ],
                                      stops: const [0.0, 0.3, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                    const SizedBox(height: 15),
                    Container(
                      constraints: const BoxConstraints(minHeight: 52, maxHeight: 140),
                      padding: const EdgeInsets.only(left: 16, right: 6, top: 6, bottom: 6),
                      decoration: BoxDecoration(
                        color: flux.surface,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: flux.border,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: flux.textPrimary.withValues(alpha: 0.03),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                inputDecorationTheme: const InputDecorationTheme(
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                minLines: 1,
                                maxLines: 4,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                style: textTheme.bodyMedium,
                                decoration: InputDecoration(
                                  hintText: AppLocalizations.of(context)!.describeAppIdea,
                                  hintStyle: textTheme.bodyMedium?.copyWith(color: flux.textSecondary),
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                  isDense: true,
                                  counterText: '',
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          FluxSendButton(
                            onTap: _sendMessage,
                            onStop: _stopGeneration,
                            isEnabled: _hasText,
                            isStreaming: _isStreaming,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, FluxColorsExtension flux) {
    return FluxEmptyState(
      icon: Icons.code_rounded,
      title: AppLocalizations.of(context)!.buildSomethingAmazing,
      subtitle: AppLocalizations.of(context)!.describeAppIdea,
    );
  }

  String _stripThinkTags(String text) {
    // Remove <think>...</think> blocks, including partial ones during streaming
    final thinkRegex = RegExp(r'<think>[\s\S]*?(?:</think>|$)', caseSensitive: false);
    return text.replaceAll(thinkRegex, '').trim();
  }

  Widget _buildBubble(_EditorMessage msg, FluxColorsExtension flux, {bool isLast = false}) {
    final isUser = msg.fromUser;
    final bottomPadding = isLast ? 0.0 : 12.0;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isError = !isUser && msg.text.startsWith('Error:');
    
    // Hide <think> tags from the display text
    final displayText = isUser ? msg.text : _stripThinkTags(msg.text);
    
    final html = !isUser ? _extractHtml(msg.text) : null;
    final explanation = !isUser && html != null ? _extractExplanation(displayText) : null;

    Widget bubbleContent;
    if (!isUser && html != null && html.isNotEmpty) {
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Show AI's explanation text (everything before the code block)
          if (explanation != null && explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                explanation,
                style: textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          // Preview card
          BouncyTap(
            onTap: () => _showPreview(context),
            scaleDown: 0.97,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: flux.textPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: flux.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [flux.textPrimary, flux.textPrimary.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.play_arrow_rounded, color: flux.background, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppLocalizations.of(context)!.previewCreation, style: textTheme.titleLarge?.copyWith(fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(AppLocalizations.of(context)!.tapToOpenApp, style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: flux.textPrimary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.arrow_forward, color: flux.textPrimary, size: 12),
                  ),
                ],
              ),
            ),
          ),
          if (isError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: BouncyTap(
                onTap: () {
                  final lastUserMsg = _messages.lastWhere((m) => m.fromUser);
                  _controller.text = lastUserMsg.text;
                  _messages.clear();
                  _sendMessage();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: flux.textPrimary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(100)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 14, color: flux.textPrimary),
                      const SizedBox(width: 6),
                      Text(AppLocalizations.of(context)!.retry, style: textTheme.labelLarge?.copyWith(color: flux.textPrimary)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    } else if (!isUser) {
      bubbleContent = Text(
        displayText,
        style: textTheme.bodyMedium?.copyWith(height: 1.4),
      );
    } else {
      bubbleContent = Text(
        displayText,
        style: textTheme.bodyMedium?.copyWith(color: isDark ? flux.textPrimary : flux.background, height: 1.4),
      );
    }

    final bubble = isUser
        ? RepaintBoundary(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? flux.surfaceSecondary : flux.textPrimary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      child: bubbleContent,
                    ),
                  ),
                ],
              ),
            ),
          )
        : RepaintBoundary(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  bubbleContent,
                  if (!isUser)
                    _buildEditorMessageFooter(msg, flux: flux, textTheme: textTheme, showTokenSpeed: _showTokenSpeed),
                ],
              ),
            ),
          );

    return RepaintBoundary(
      child: BouncyFadeSlide(
        duration: FluxDurations.normal,
        slideOffset: 12,
        child: GestureDetector(
          onLongPress: null,
          child: bubble,
        ),
      ),
    );
  }

  void _regenerateEditor(_EditorMessage msg) {
    final msgIndex = _messages.indexOf(msg);
    if (msgIndex < 0) return;

    final userMsg = _messages.sublist(0, msgIndex).lastWhere((m) => m.fromUser, orElse: () => _messages.first);
    _messages.removeRange(msgIndex, _messages.length);
    _controller.text = userMsg.text;
    _focusNode.requestFocus();
    if (mounted) setState(() => _hasText = true);
    _sendMessage();
  }

  Widget _buildEditorMessageFooter(_EditorMessage msg, {required FluxColorsExtension flux, required TextTheme textTheme, bool showTokenSpeed = false}) {
    final hasStats = showTokenSpeed && (msg.outputTokPerSec > 0 || msg.outputTokens > 0);
    final tg = msg.outputTokPerSec > 0 ? '${msg.outputTokPerSec.toStringAsFixed(1)} t/s' : null;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          BouncyTap(
            onTap: () {
              Clipboard.setData(ClipboardData(text: msg.text));
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context)!.copiedToClipboard, style: textTheme.bodySmall),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  margin: const EdgeInsets.all(20),
                ),
              );
            },
            scaleDown: 0.9,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.content_copy, size: 18, color: flux.textPrimary),
            ),
          ),
          const SizedBox(width: 10),
          BouncyTap(
            onTap: () => _regenerateEditor(msg),
            scaleDown: 0.9,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.refresh, size: 18, color: flux.textPrimary),
            ),
          ),
          if (hasStats) ...[
            const SizedBox(width: 10),
            Text(
              '${tg != null ? 'Output Speed: $tg' : ''}${msg.outputTokens > 0 ? '  \u2022  ${msg.outputTokens} tok' : ''}',
              style: textTheme.labelMedium?.copyWith(
                color: flux.textSecondary.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStreamingBubble(FluxColorsExtension flux, bool isLast) {
    final textTheme = Theme.of(context).textTheme;
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0.0 : 12.0),
        child: ValueListenableBuilder<String>(
          valueListenable: _streamingTextNotifier,
          builder: (context, streamingText, _) {
            final stripped = _stripThinkTags(streamingText);
            if (streamingText.isEmpty || (stripped.isEmpty && streamingText.isNotEmpty)) {
              return const FluxThinkingIndicator();
            }
            // Plain text during streaming — rich markdown parsing is too
            // expensive for long outputs and causes crashes.
            return Text(
              stripped,
              style: textTheme.bodyMedium?.copyWith(height: 1.4),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// MESSAGE MODEL
// ============================================================================
class _EditorMessage {
  final String text;
  final bool fromUser;
  final DateTime time;
  final double outputTokPerSec;
  final int outputTokens;
  _EditorMessage({
    required this.text,
    required this.fromUser,
    required this.time,
    this.outputTokPerSec = 0,
    this.outputTokens = 0,
  });
}

// ============================================================================
// PREVIEW SCREEN
// ============================================================================
class _PreviewScreen extends StatelessWidget {
  final WebViewController webViewController;
  final VoidCallback onClose;
  const _PreviewScreen({required this.webViewController, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: flux.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  BouncyTap(
                    onTap: onClose,
                    scaleDown: 0.85,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: flux.border),
                      ),
                      child: Icon(Icons.close, size: 18, color: flux.textPrimary),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        AppLocalizations.of(context)!.preview,
                        style: textTheme.titleLarge,
                      ),
                    ),
                  ),
                  const SizedBox(width: 36), // Spacer to balance the X button
                ],
              ),
            ),
            Divider(color: flux.border, height: 1, thickness: 0.5),
            // WebView
            Expanded(
              child: RepaintBoundary(
                child: WebViewWidget(controller: webViewController),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

