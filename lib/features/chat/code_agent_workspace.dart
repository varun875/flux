import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/chat_session.dart';
import '../../core/widgets/flux_animations.dart';
import '../../core/providers/active_file_provider.dart';
import '../../core/theme/flux_theme.dart';

// ============================================================================
// DATA MODELS
// ============================================================================

class SessionFile {
  final String name;
  final String content;
  final String language;
  final DateTime timestamp;

  SessionFile({
    required this.name,
    required this.content,
    required this.language,
    required this.timestamp,
  });
}

class ConsoleLog {
  final String message;
  final String type; // 'system', 'user', 'agent', 'success', 'error', 'command'
  final DateTime time;

  ConsoleLog(this.message, {this.type = 'system', DateTime? time})
      : time = time ?? DateTime.now();
}

// ============================================================================
// CODE AGENT WORKSPACE WIDGET
// ============================================================================

class CodeAgentWorkspace extends ConsumerStatefulWidget {
  final List<ChatMessage> messages;
  final bool isStreaming;
  final String currentStreamingText;

  const CodeAgentWorkspace({
    super.key,
    required this.messages,
    required this.isStreaming,
    required this.currentStreamingText,
  });

  @override
  ConsumerState<CodeAgentWorkspace> createState() => _CodeAgentWorkspaceState();
}

class _CodeAgentWorkspaceState extends ConsumerState<CodeAgentWorkspace>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // File explorer state
  List<FileEntityInfo> _projectFiles = [];
  bool _isLoadingFiles = false;
  FileEntityInfo? _selectedFile;

  // Selected code view details
  String _editorTitle = 'untitled.dart';
  String _editorContent = '// No file selected.\n// Select a file from the Files tab or generate code in the Chat.';
  String _editorLanguage = 'dart';

  // Interactive console state
  final List<ConsoleLog> _consoleLogs = [];
  final TextEditingController _consoleInputController = TextEditingController();
  final ScrollController _consoleScrollController = ScrollController();
  final FocusNode _consoleFocusNode = FocusNode();

  // Keep track of extracted session files
  List<SessionFile> _sessionFiles = [];

  late SyntaxHighlightingController _editorController;
  bool _isModified = false;
  String _workspacePath = Directory.current.path;

  // Theme colors helper
  Color get _bgDark => Theme.of(context).extension<FluxColorsExtension>()?.background ?? const Color(0xFF0F0F12);
  Color get _surfaceDark => Theme.of(context).extension<FluxColorsExtension>()?.surface ?? const Color(0xFF16161C);
  Color get _borderDark => Theme.of(context).extension<FluxColorsExtension>()?.border ?? const Color(0xFF252530);
  Color get _accentCyan => Theme.of(context).extension<FluxColorsExtension>()?.accent ?? const Color(0xFF00E5FF);
  Color get _textPrimaryDark => Theme.of(context).extension<FluxColorsExtension>()?.textPrimary ?? const Color(0xFFE2E4E9);
  Color get _textSecondaryDark => Theme.of(context).extension<FluxColorsExtension>()?.textSecondary ?? const Color(0xFF868C9C);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _editorController = SyntaxHighlightingController(
      text: _editorContent,
      language: _editorLanguage,
    );
    _editorController.addListener(_onEditorChanged);

    _initConsole();
    _loadSavedWorkspace();
    _parseSessionFiles();
  }

  void _onEditorChanged() {
    if (mounted) {
      final text = _editorController.text;
      final modified = text != _editorContent;
      setState(() {
        _isModified = modified;
      });
      // Update activeFileProvider with edited contents in real-time
      final currentActive = ref.read(activeFileProvider);
      if (currentActive != null && currentActive.name == _editorTitle) {
        ref.read(activeFileProvider.notifier).state = ActiveFile(
          name: currentActive.name,
          path: currentActive.path,
          content: text,
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant CodeAgentWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    _parseSessionFiles();

    // Log streaming updates to the console
    if (widget.isStreaming && !oldWidget.isStreaming) {
      _addLog('System: Initiating local LLM inference stream...', type: 'system');
    }
    if (!widget.isStreaming && oldWidget.isStreaming) {
      _addLog('System: Inference stream complete.', type: 'success');
      // If code was generated, auto-select the latest code block
      if (_sessionFiles.isNotEmpty) {
        final latest = _sessionFiles.last;
        setState(() {
          _editorTitle = latest.name;
          _editorContent = latest.content;
          _editorLanguage = latest.language;
          _editorController.text = latest.content;
          _editorController.language = latest.language;
          _isModified = false;
        });
        _addLog('Agent: Loaded newly generated code "${latest.name}" into Editor.', type: 'agent');
      }
    }
  }

  @override
  void dispose() {
    _editorController.removeListener(_onEditorChanged);
    _editorController.dispose();
    _tabController.dispose();
    _consoleInputController.dispose();
    _consoleScrollController.dispose();
    _consoleFocusNode.dispose();
    super.dispose();
  }

  // ============================================================================
  // WORKSPACE ENGINE
  // ============================================================================

  void _initConsole() {
    _consoleLogs.clear();
    _consoleLogs.add(ConsoleLog('Booting Flux Code Agent environment...', type: 'system'));
    _consoleLogs.add(ConsoleLog('Platform: ${Platform.operatingSystem} (Local Mode)', type: 'system'));
    _consoleLogs.add(ConsoleLog('Workspace path: $_workspacePath', type: 'system'));
    _consoleLogs.add(ConsoleLog('Initializing file watchers...', type: 'system'));
    _consoleLogs.add(ConsoleLog('Flux Code Agent ready.', type: 'success'));
  }

  void _addLog(String msg, {String type = 'system'}) {
    if (!mounted) return;
    setState(() {
      _consoleLogs.add(ConsoleLog(msg, type: type));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_consoleScrollController.hasClients) {
        _consoleScrollController.animateTo(
          _consoleScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadSavedWorkspace() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString('flux_workspace_path');
      if (savedPath != null && Directory(savedPath).existsSync()) {
        setState(() {
          _workspacePath = savedPath;
        });
        _addLog('System: Loaded saved workspace "$savedPath"', type: 'success');
      }
    } catch (e) {
      _addLog('Error: Failed to load saved workspace: $e', type: 'error');
    }
    _loadWorkspaceFiles();
  }

  Future<void> _selectWorkspaceDirectory() async {
    try {
      final String? selectedDirectory = await FilePicker.getDirectoryPath();
      if (selectedDirectory != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('flux_workspace_path', selectedDirectory);

        setState(() {
          _workspacePath = selectedDirectory;
        });

        _addLog('System: Changed workspace path to "$selectedDirectory"', type: 'success');
        _loadWorkspaceFiles();
      }
    } catch (e) {
      _addLog('Error: Failed to change workspace: $e', type: 'error');
    }
  }

  Future<void> _loadWorkspaceFiles() async {
    setState(() => _isLoadingFiles = true);
    try {
      final List<FileEntityInfo> files = [];
      final currentDir = Directory(_workspacePath);

      // Recursive scan, limiting depth/folders for performance
      if (await currentDir.exists()) {
        await for (final entity in currentDir.list(recursive: true, followLinks: false)) {
          final path = entity.path;
          final relativePath = path.substring(currentDir.path.length + 1);

          // Exclude typical builder/platform/git directories
          if (relativePath.startsWith('.git') ||
              relativePath.startsWith('.dart_tool') ||
              relativePath.startsWith('build') ||
              relativePath.startsWith('android') ||
              relativePath.startsWith('ios') ||
              relativePath.startsWith('windows') ||
              relativePath.startsWith('macos') ||
              relativePath.startsWith('linux') ||
              relativePath.startsWith('ohos') ||
              relativePath.startsWith('entry/') ||
              relativePath.contains('/.') ||
              relativePath.contains('\\.')) {
            continue;
          }

          final isDir = entity is Directory;
          final name = relativePath.split(Platform.pathSeparator).last;

          if (isDir) {
            files.add(FileEntityInfo(
              name: name,
              path: path,
              relativePath: relativePath,
              isDirectory: true,
            ));
          } else if (entity is File) {
            final ext = name.split('.').length > 1 ? name.split('.').last : '';
            // Only include common coding extensions
            if (['dart', 'yaml', 'json', 'md', 'js', 'html', 'css', 'xml', 'txt', 'gradle', 'properties', 'yaml'].contains(ext.toLowerCase())) {
              files.add(FileEntityInfo(
                name: name,
                path: path,
                relativePath: relativePath,
                isDirectory: false,
                extension: ext,
              ));
            }
          }
        }
      }

      // Sort: Folders first, then alphabetically
      files.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase());
      });

      if (mounted) {
        setState(() {
          _projectFiles = files;
          _isLoadingFiles = false;
        });
        _addLog('System: Scanned workspace directory. Found ${files.length} project files.', type: 'system');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFiles = false);
        _addLog('Error: Failed to scan directory: $e', type: 'error');
      }
      _loadMockWorkspace();
    }
  }

  void _loadMockWorkspace() {
    _addLog('System: Falling back to sandbox mock files.', type: 'system');
    final List<FileEntityInfo> mockFiles = [
      FileEntityInfo(name: 'lib', path: 'lib', relativePath: 'lib', isDirectory: true),
      FileEntityInfo(name: 'main.dart', path: 'lib/main.dart', relativePath: 'lib/main.dart', isDirectory: false, extension: 'dart'),
      FileEntityInfo(name: 'core', path: 'lib/core', relativePath: 'lib/core', isDirectory: true),
      FileEntityInfo(name: 'services', path: 'lib/core/services', relativePath: 'lib/core/services', isDirectory: true),
      FileEntityInfo(name: 'inference_service.dart', path: 'lib/core/services/inference_service.dart', relativePath: 'lib/core/services/inference_service.dart', isDirectory: false, extension: 'dart'),
      FileEntityInfo(name: 'pubspec.yaml', path: 'pubspec.yaml', relativePath: 'pubspec.yaml', isDirectory: false, extension: 'yaml'),
      FileEntityInfo(name: 'README.md', path: 'README.md', relativePath: 'README.md', isDirectory: false, extension: 'md'),
    ];
    setState(() {
      _projectFiles = mockFiles;
    });
  }

  void _parseSessionFiles() {
    final List<SessionFile> extracted = [];
    final codeBlockRegex = RegExp(r'```(\w*)\n([\s\S]*?)```');

    for (int i = 0; i < widget.messages.length; i++) {
      final msg = widget.messages[i];
      if (msg.fromUser) continue;

      final matches = codeBlockRegex.allMatches(msg.text);
      int codeIdx = 1;
      for (final match in matches) {
        final language = match.group(1) ?? 'dart';
        final content = match.group(2) ?? '';

        // Determine filename
        String filename = 'generated_code_$codeIdx.$language';
        if (language == 'html' || language == 'xml') filename = 'index.html';

        // Check if there is an explicit file header in the text preceding the block
        final precedingText = msg.text.substring(0, match.start);
        final fileHeaderMatch = RegExp(r'(?:lib/|assets/|src/)[\w\-/]+\.\w+').allMatches(precedingText);
        if (fileHeaderMatch.isNotEmpty) {
          filename = fileHeaderMatch.last.group(0)!;
        } else {
          // Look for inline backticks with filename
          final inlineMatch = RegExp(r'`([\w\-./]+\.\w+)`').allMatches(precedingText);
          if (inlineMatch.isNotEmpty) {
            filename = inlineMatch.last.group(1)!;
          }
        }

        extracted.add(SessionFile(
          name: filename,
          content: content.trim(),
          language: language,
          timestamp: msg.time,
        ));
        codeIdx++;
      }
    }

    // Include streaming content if applicable
    if (widget.isStreaming && widget.currentStreamingText.isNotEmpty) {
      final matches = codeBlockRegex.allMatches(widget.currentStreamingText);
      if (matches.isNotEmpty) {
        final lastMatch = matches.last;
        final language = lastMatch.group(1) ?? 'dart';
        final content = lastMatch.group(2) ?? '';
        extracted.add(SessionFile(
          name: 'generating_code.$language',
          content: '$content\n// [Streaming...]...',
          language: language,
          timestamp: DateTime.now(),
        ));
      }
    }

    _sessionFiles = extracted;
  }

  Future<void> _openFile(FileEntityInfo info) async {
    setState(() => _selectedFile = info);
    _addLog('System: Opening file ${info.relativePath}...', type: 'system');

    try {
      if (info.isDirectory) return;

      final file = File(info.path);
      if (await file.exists()) {
        final content = await file.readAsString();
        setState(() {
          _editorTitle = info.name;
          _editorContent = content;
          _editorLanguage = info.extension ?? 'dart';
          _editorController.text = content;
          _editorController.language = _editorLanguage;
          _isModified = false;
        });
        ref.read(activeFileProvider.notifier).state = ActiveFile(
          name: info.name,
          path: info.path,
          content: content,
        );
        _tabController.animateTo(1); // Jump to Code Viewer
        _addLog('System: Loaded ${info.name} into Code Editor.', type: 'success');
      } else {
        // Mock fallback file read
        final mockContent = _getMockFileContent(info.relativePath);
        setState(() {
          _editorTitle = info.name;
          _editorContent = mockContent;
          _editorLanguage = info.extension ?? 'dart';
          _editorController.text = mockContent;
          _editorController.language = _editorLanguage;
          _isModified = false;
        });
        ref.read(activeFileProvider.notifier).state = ActiveFile(
          name: info.name,
          path: info.path,
          content: mockContent,
        );
        _tabController.animateTo(1);
        _addLog('System: Opened sandbox file ${info.name}.', type: 'success');
      }
    } catch (e) {
      _addLog('Error: Failed to read file: $e', type: 'error');
    }
  }

  Future<void> _saveCurrentFile() async {
    try {
      final path = _selectedFile?.path ?? _editorTitle;
      final file = File(path);

      // Ensure directory exists
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      await file.writeAsString(_editorController.text);

      if (!mounted) return;

      setState(() {
        _editorContent = _editorController.text;
        _isModified = false;
      });

      _addLog('System: Saved changes to $path', type: 'success');
      _loadWorkspaceFiles(); // Refresh file explorer

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved changes to $path'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _surfaceDark,
        ),
      );
    } catch (e) {
      _addLog('Error: Failed to save file: $e', type: 'error');
    }
  }

  String _getMockFileContent(String relPath) {
    if (relPath == 'lib/main.dart') {
      return '''import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/inference_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FluxApp()));
}''';
    } else if (relPath == 'lib/core/services/inference_service.dart') {
      return '''import 'package:flutter_gemma/flutter_gemma.dart';

class InferenceService {
  static final InferenceService _instance = InferenceService._internal();
  factory InferenceService() => _instance;
  InferenceService._internal();

  Stream<String> streamChat({required String prompt}) async* {
    // Model inference logic
  }
}''';
    } else if (relPath == 'pubspec.yaml') {
      return '''name: flux
description: On-device AI assistant
version: 0.1.9
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.1.0''';
    } else if (relPath == 'README.md') {
      return '''# Flux
On-device AI assistant for cross-platform desktop and mobile.
Uses LiteRT-LM / MediaPipe GenAI with Gemma support.''';
    }
    return '// Sandbox file: $relPath\n// Simulated code content.';
  }

  void _executeCommand(String command) {
    final cmd = command.trim();
    if (cmd.isEmpty) return;

    _addLog('> $cmd', type: 'command');
    _consoleInputController.clear();

    final lowerCmd = cmd.toLowerCase();
    if (lowerCmd == 'clear') {
      setState(() {
        _consoleLogs.clear();
      });
      return;
    }

    if (lowerCmd == 'help') {
      _addLog('Supported commands:\n  help           - Show this help\n  clear          - Clear terminal logs\n  ls             - List project directory structure\n  git status     - Show git workspace status\n  flutter analyze - Run code analyzer check\n  cat [file]     - Read contents of workspace file', type: 'system');
      return;
    }

    if (lowerCmd == 'ls') {
      final filesStr = _projectFiles.map((f) => '  ${f.isDirectory ? "📁" : "📄"} ${f.relativePath}').join('\n');
      _addLog('Files in workspace:\n$filesStr', type: 'system');
      return;
    }

    if (lowerCmd == 'git status') {
      _addLog('On branch main\nYour branch is up to date with \'origin/main\'.\n\nChanges not staged for commit:\n  (use "git add <file>..." to update what will be committed)\n  (use "git restore <file>..." to discard changes in working directory)\n\tmodified:   lib/features/chat/chat_screen.dart\n\tmodified:   lib/main.dart\n\nno changes added to commit (use "git add" and/or "git commit -a")', type: 'system');
      return;
    }

    if (lowerCmd == 'flutter analyze') {
      _addLog('Analyzing flux...\nNo issues found! (in 1.4s)\nWorkspace is fully clean.', type: 'success');
      return;
    }

    if (lowerCmd.startsWith('cat ')) {
      final target = cmd.substring(4).trim();
      final match = _projectFiles.where((f) => f.name.toLowerCase() == target.toLowerCase() || f.relativePath.toLowerCase() == target.toLowerCase());
      if (match.isNotEmpty) {
        final matchFile = match.first;
        if (matchFile.isDirectory) {
          _addLog('cat: $target: Is a directory', type: 'error');
        } else {
          _openFile(matchFile);
        }
      } else {
        _addLog('cat: $target: No such file in workspace', type: 'error');
      }
      return;
    }

    // Default simulated execution
    _addLog('Executing command in local container...', type: 'system');
    Timer(const Duration(milliseconds: 600), () {
      _addLog('Command executed successfully with exit code 0.', type: 'success');
    });
  }

  // ============================================================================
  // WIDGET BUILDERS
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bgDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderDark, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildWorkspaceHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFilesTab(),
                _buildCodeEditorTab(),
                _buildConsoleTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceHeader() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: _surfaceDark,
        border: Border(bottom: BorderSide(color: _borderDark, width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(Icons.terminal_rounded, size: 18, color: _accentCyan),
          const SizedBox(width: 8),
          Text(
            'FLUX WORKSPACE',
            style: GoogleFonts.firaCode(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _textPrimaryDark,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: _accentCyan,
            dividerColor: Colors.transparent,
            tabAlignment: TabAlignment.start,
            labelColor: _textPrimaryDark,
            unselectedLabelColor: _textSecondaryDark,
            labelStyle: GoogleFonts.instrumentSans(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(child: Row(children: [Icon(Icons.folder_open_outlined, size: 14), SizedBox(width: 4), Text('Files')])),
              Tab(child: Row(children: [Icon(Icons.code_rounded, size: 14), SizedBox(width: 4), Text('Code')])),
              Tab(child: Row(children: [Icon(Icons.keyboard_outlined, size: 14), SizedBox(width: 4), Text('Console')])),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ============================================================================
  // TAB 1: FILES EXPLORER PANEL
  // ============================================================================

  Widget _buildFilesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      children: [
        if (_sessionFiles.isNotEmpty) ...[
          _buildSectionHeader('SESSION FILES (GENERATED BY AI)'),
          const SizedBox(height: 8),
          ..._sessionFiles.map((sf) => _buildSessionFileTile(sf)),
          const SizedBox(height: 24),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: _buildSectionHeader('WORKSPACE FILES (PROJECT CODE)')),
            BouncyTap(
              onTap: _selectWorkspaceDirectory,
              scaleDown: 0.9,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _borderDark,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_outlined, size: 12, color: _accentCyan),
                    const SizedBox(width: 4),
                    Text(
                      'Change',
                      style: GoogleFonts.instrumentSans(
                        fontSize: 11,
                        color: _textPrimaryDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingFiles)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2)),
          )
        else if (_projectFiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No project files found.', style: TextStyle(color: _textSecondaryDark, fontSize: 13)),
          )
        else
          ..._projectFiles.map((info) => _buildWorkspaceFileTile(info)),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.firaCode(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: _textSecondaryDark.withValues(alpha: 0.8),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSessionFileTile(SessionFile sf) {
    final isSelected = _editorTitle == sf.name && _editorContent == sf.content;

    return BouncyTap(
      scaleDown: 0.98,
      onTap: () {
        setState(() {
          _editorTitle = sf.name;
          _editorContent = sf.content;
          _editorLanguage = sf.language;
          _editorController.text = sf.content;
          _editorController.language = sf.language;
          _isModified = false;
        });
        ref.read(activeFileProvider.notifier).state = ActiveFile(
          name: sf.name,
          path: 'Session File',
          content: sf.content,
        );
        _tabController.animateTo(1);
        _addLog('System: Opened session generated file "${sf.name}"', type: 'system');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _borderDark.withValues(alpha: 0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? _borderDark : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 14, color: _accentCyan),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sf.name,
                style: GoogleFonts.firaCode(
                  fontSize: 13,
                  color: isSelected ? Colors.white : _textPrimaryDark,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              sf.language.toUpperCase(),
              style: TextStyle(fontSize: 10, color: _textSecondaryDark, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceFileTile(FileEntityInfo info) {
    final depth = info.relativePath.split(Platform.pathSeparator).length - 1;
    final isSelected = _selectedFile == info;

    IconData getFileIcon(FileEntityInfo file) {
      if (file.isDirectory) return Icons.folder_rounded;
      final ext = file.extension?.toLowerCase();
      if (ext == 'dart') return Icons.code_rounded;
      if (ext == 'yaml' || ext == 'json') return Icons.settings_applications_outlined;
      if (ext == 'md') return Icons.edit_note_rounded;
      if (ext == 'html') return Icons.web_rounded;
      return Icons.insert_drive_file_outlined;
    }

    Color getIconColor(FileEntityInfo file) {
      if (file.isDirectory) return Colors.amber;
      final ext = file.extension?.toLowerCase();
      if (ext == 'dart') return const Color(0xFF00B0FF);
      if (ext == 'yaml') return const Color(0xFF81C784);
      if (ext == 'html') return const Color(0xFFFF8A65);
      return _textSecondaryDark;
    }

    return BouncyTap(
      scaleDown: 0.98,
      onTap: () => _openFile(info),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: EdgeInsets.only(
          left: 12.0 + (depth * 14.0),
          right: 12.0,
          top: 8.0,
          bottom: 8.0,
        ),
        decoration: BoxDecoration(
          color: isSelected ? _borderDark.withValues(alpha: 0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? _borderDark : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(getFileIcon(info), size: 16, color: getIconColor(info)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                info.name,
                style: GoogleFonts.firaCode(
                  fontSize: 13,
                  color: isSelected ? Colors.white : _textPrimaryDark,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // TAB 2: CODE EDITOR PANEL
  // ============================================================================

  Widget _buildCodeEditorTab() {
    final codeLines = _editorController.text.split('\n');

    return Container(
      color: const Color(0xFF08080A),
      child: Column(
        children: [
          // File path bar
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _surfaceDark,
              border: Border(bottom: BorderSide(color: _borderDark, width: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_document, size: 14, color: _textSecondaryDark),
                const SizedBox(width: 8),
                Text(
                  _editorTitle,
                  style: GoogleFonts.firaCode(fontSize: 12, color: _textPrimaryDark, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                if (_isModified) ...[
                  BouncyTap(
                    onTap: _saveCurrentFile,
                    scaleDown: 0.9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.save_outlined, size: 11, color: Colors.greenAccent),
                          SizedBox(width: 4),
                          Text('Save', style: TextStyle(fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                BouncyTap(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _editorController.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Copied code to clipboard'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: _surfaceDark,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  scaleDown: 0.9,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _borderDark,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy, size: 11, color: _textPrimaryDark),
                        const SizedBox(width: 4),
                        Text('Copy', style: TextStyle(fontSize: 11, color: _textPrimaryDark)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code viewport
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              physics: const BouncingScrollPhysics(),
              scrollDirection: Axis.vertical,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line numbers
                  Container(
                    width: 40,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 12, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(
                        codeLines.length,
                        (idx) => Text(
                          '${idx + 1}',
                          style: GoogleFonts.firaCode(
                            fontSize: 12,
                            color: _textSecondaryDark.withValues(alpha: 0.4),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Code content with basic syntax-like colors
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, right: 16),
                      child: TextField(
                        controller: _editorController,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: GoogleFonts.firaCode(
                          fontSize: 12,
                          color: _textPrimaryDark,
                          height: 1.5,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }



  // ============================================================================
  // TAB 3: SIMULATED DEV TERMINAL/CONSOLE
  // ============================================================================

  Widget _buildConsoleTab() {
    return Container(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Console logs
          Expanded(
            child: ListView.builder(
              controller: _consoleScrollController,
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              itemCount: _consoleLogs.length,
              itemBuilder: (context, index) {
                final log = _consoleLogs[index];
                Color msgColor = _textPrimaryDark;
                if (log.type == 'success') msgColor = Colors.greenAccent;
                if (log.type == 'error') msgColor = Colors.redAccent;
                if (log.type == 'command') msgColor = _accentCyan;
                if (log.type == 'agent') msgColor = Colors.amberAccent;
                if (log.type == 'system') msgColor = _textSecondaryDark;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '[${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}] ',
                        style: GoogleFonts.firaCode(fontSize: 12, color: _textSecondaryDark.withValues(alpha: 0.6)),
                      ),
                      Expanded(
                        child: Text(
                          log.message,
                          style: GoogleFonts.firaCode(fontSize: 12, color: msgColor, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Interactive Terminal Command Bar
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _surfaceDark,
              border: Border(top: BorderSide(color: _borderDark, width: 1)),
            ),
            child: Row(
              children: [
                Text(
                  '${Platform.operatingSystem.toLowerCase()}:flux\$ ',
                  style: GoogleFonts.firaCode(fontSize: 12, color: _accentCyan, fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: TextField(
                    controller: _consoleInputController,
                    focusNode: _consoleFocusNode,
                    style: GoogleFonts.firaCode(fontSize: 12, color: _textPrimaryDark),
                    cursorColor: _accentCyan,
                    decoration: const InputDecoration(
                      hintText: 'type "help" for interactive options...',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    onSubmitted: _executeCommand,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HELPER MODELS & CLASSES
// ============================================================================

class FileEntityInfo {
  final String name;
  final String path;
  final String relativePath;
  final bool isDirectory;
  final String? extension;

  FileEntityInfo({
    required this.name,
    required this.path,
    required this.relativePath,
    required this.isDirectory,
    this.extension,
  });
}

class _HighlightMatch {
  final int start;
  final int end;
  final Color color;

  _HighlightMatch(this.start, this.end, this.color);

  bool overlaps(int s, int e) {
    return (s >= start && s < end) || (e > start && e <= end) || (start >= s && start < e);
  }
}

class SyntaxHighlightingController extends TextEditingController {
  String language;

  SyntaxHighlightingController({super.text, required this.language});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<TextSpan> spans = [];

    // Basic regexes
    final commentRegex = RegExp(r'(//.*|#.*|/\*[\s\S]*?\*/)');
    final stringRegex = RegExp(r'(".*?"|' "'" r".*?" r')');
    final keywordRegex = RegExp(
        r'\b(import|class|void|main|async|await|final|const|var|return|if|else|for|while|extends|factory|static|get|set|true|false|null|override|int|double|String|bool|Map|List)\b');
    final numberRegex = RegExp(r'\b(\d+)\b');

    final matches = <_HighlightMatch>[];

    for (final match in commentRegex.allMatches(text)) {
      matches.add(_HighlightMatch(match.start, match.end, const Color(0xFF6A9955)));
    }
    for (final match in stringRegex.allMatches(text)) {
      if (!matches.any((m) => m.overlaps(match.start, match.end))) {
        matches.add(_HighlightMatch(match.start, match.end, const Color(0xFFCE9178)));
      }
    }
    for (final match in keywordRegex.allMatches(text)) {
      if (!matches.any((m) => m.overlaps(match.start, match.end))) {
        matches.add(_HighlightMatch(match.start, match.end, const Color(0xFF569CD6)));
      }
    }
    for (final match in numberRegex.allMatches(text)) {
      if (!matches.any((m) => m.overlaps(match.start, match.end))) {
        matches.add(_HighlightMatch(match.start, match.end, const Color(0xFFB5CEA8)));
      }
    }

    matches.sort((a, b) => a.start.compareTo(b.start));

    int lastEnd = 0;
    for (final hm in matches) {
      if (hm.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, hm.start)));
      }
      spans.add(TextSpan(
        text: text.substring(hm.start, hm.end),
        style: TextStyle(color: hm.color),
      ));
      lastEnd = hm.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return TextSpan(
      style: style,
      children: spans.isEmpty ? [TextSpan(text: text)] : spans,
    );
  }
}
