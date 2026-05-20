import 'dart:io' show Platform;

class CodeAgentService {
  static bool get isComputerPlatform =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static const String assistantPrompt =
      'You are Flux, a helpful and friendly AI assistant. '
      'IMPORTANT: You have perfect memory of this conversation. '
      'The full conversation history is provided to you with every message, '
      'so you can reference anything said earlier. '
      'Never claim you do not remember something from this chat -- you do. '
      'Answer concisely and accurately.';

  static const String codeAgentPrompt =
      'You are Flux Code Agent, an expert software engineering assistant for '
      'computer platforms (Windows, macOS, and Linux). '
      'Focus on implementation details, debugging, and practical execution. '
      'When giving shell commands, prefer safe, incremental commands and note '
      'platform-specific variants when it matters. '
      'For code changes, prioritize correctness, readability, and minimal '
      'diffs. Ask clarifying questions only when required to avoid risky '
      'assumptions.';

  static String getDynamicCodeAgentPrompt({
    required String workspacePath,
    required List<String> workspaceFiles,
    String? activeFileName,
    String? activeFileContent,
  }) {
    String filesSummary = '';
    if (workspaceFiles.isNotEmpty) {
      if (workspaceFiles.length > 50) {
        filesSummary = '${workspaceFiles.sublist(0, 50).join('\n')}\n... and ${workspaceFiles.length - 50} more files.';
      } else {
        filesSummary = workspaceFiles.join('\n');
      }
    } else {
      filesSummary = 'No source files found in workspace.';
    }

    String activeFileSection = '';
    if (activeFileName != null && activeFileContent != null) {
      activeFileSection = '\n\n'
          'CURRENT OPEN FILE: $activeFileName\n'
          'Here is the current content of $activeFileName:\n'
          '```\n'
          '$activeFileContent\n'
          '```';
    }

    return '$codeAgentPrompt\n\n'
        'You have direct read access to the local workspace via the Flux application workspace.\n'
        'Current Workspace Path: $workspacePath\n'
        'Here is the list of files in the user\'s current workspace:\n'
        '```\n'
        '$filesSummary\n'
        '```'
        '$activeFileSection\n\n'
        'IMPORTANT: Always address the workspace files directly in your answer. You can reference them by name or path. '
        'If the user asks to modify a file, you should write complete, runnable code inside fenced markdown blocks, and specify the file name clearly.';
  }
}
