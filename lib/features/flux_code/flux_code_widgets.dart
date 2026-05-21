import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/chat_session.dart';
import '../../core/models/flux_code_project.dart';
import '../../core/theme/flux_theme.dart';
import '../../core/widgets/flux_animations.dart';

// ============================================================================
// Flux Code — minimal Codex-style layout primitives
// A dedicated UI for Flux Code (the on-device coding agent), inspired by
// Codex / Claude Code / Cursor. Used only in desktop fluxCode mode.
// ============================================================================

/// Left navigation column inside the Flux Code workspace.
/// Projects are listed at the top; each project shows its chats nested
/// underneath. Hovering a project row reveals compose (pencil) and 3-dot menu.
class FluxCodeSidebar extends StatelessWidget {
  final VoidCallback onNewChat;
  final VoidCallback onAddProject;
  final List<FluxCodeProject> projects;
  final String? activeProjectId;
  final ValueChanged<FluxCodeProject>? onSelectProject;
  final ValueChanged<FluxCodeProject>? onRenameProject;
  final ValueChanged<FluxCodeProject>? onDeleteProject;
  final List<ChatSession> conversations;
  final String? activeConversationId;
  final ValueChanged<ChatSession>? onSelectConversation;
  final ValueChanged<ChatSession>? onRenameConversation;
  final ValueChanged<ChatSession>? onDeleteConversation;

  const FluxCodeSidebar({
    super.key,
    required this.onNewChat,
    required this.onAddProject,
    required this.projects,
    this.activeProjectId,
    this.onSelectProject,
    this.onRenameProject,
    this.onDeleteProject,
    this.conversations = const [],
    this.activeConversationId,
    this.onSelectConversation,
    this.onRenameConversation,
    this.onDeleteConversation,
  });

  List<ChatSession> _chatsForProject(String projectId) {
    return conversations
        .where((c) => c.projectId == projectId)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;

    // Separate chats with no project (pre-existing data)
    final noProjectChats = conversations.where((c) => c.projectId == null).toList();

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: flux.background,
        border: Border(
          right: BorderSide(color: flux.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Projects section header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
            child: Row(
              children: [
                Text(
                  'Projects',
                  style: textTheme.labelSmall?.copyWith(
                    color: flux.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Add project',
                  child: BouncyTap(
                    onTap: onAddProject,
                    scaleDown: 0.9,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: Icon(Icons.add_rounded,
                          size: 16, color: flux.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (projects.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 16, 8),
              child: Text(
                'Click + to add a folder',
                style: textTheme.bodySmall?.copyWith(
                  color: flux.textTertiary,
                ),
              ),
            ),
          // Projects with nested chats
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final project in projects)
                  _ProjectSection(
                    project: project,
                    isSelected: project.id == activeProjectId,
                    chats: _chatsForProject(project.id),
                    activeConversationId: activeConversationId,
                    onSelectProject: () => onSelectProject?.call(project),
                    onNewChat: onNewChat,
                    onRename: onRenameProject == null
                        ? null
                        : () => onRenameProject!(project),
                    onDelete: onDeleteProject == null
                        ? null
                        : () => onDeleteProject!(project),
                    onSelectConversation: onSelectConversation,
                  ),
                if (noProjectChats.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Text(
                      'Unassigned chats',
                      style: textTheme.labelSmall?.copyWith(
                        color: flux.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  for (final c in noProjectChats)
                    _ChatRow(
                      title: c.title,
                      isSelected: c.id == activeConversationId,
                      onTap: () => onSelectConversation?.call(c),
                      onRename: onRenameConversation == null
                          ? null
                          : () => onRenameConversation!(c),
                      onDelete: onDeleteConversation == null
                          ? null
                          : () => onDeleteConversation!(c),
                    ),
                ],
                if (projects.isEmpty && noProjectChats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'No chats yet',
                      style: textTheme.bodySmall?.copyWith(
                        color: flux.textTertiary,
                      ),
                    ),
                  ),
                // Always-visible new-chat button at the bottom
                if (projects.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: _BottomNewChatButton(onTap: onNewChat),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Project header row with hover-revealed pencil (compose) and 3-dot menu,
/// plus nested chat rows underneath.
class _ProjectSection extends StatefulWidget {
  final FluxCodeProject project;
  final bool isSelected;
  final List<ChatSession> chats;
  final String? activeConversationId;
  final VoidCallback onSelectProject;
  final VoidCallback onNewChat;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final ValueChanged<ChatSession>? onSelectConversation;

  const _ProjectSection({
    required this.project,
    required this.isSelected,
    required this.chats,
    this.activeConversationId,
    required this.onSelectProject,
    required this.onNewChat,
    this.onRename,
    this.onDelete,
    this.onSelectConversation,
  });

  @override
  State<_ProjectSection> createState() => _ProjectSectionState();
}

class _ProjectSectionState extends State<_ProjectSection> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelectProject,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? flux.surface
                    : (_hovering ? flux.surface.withValues(alpha: 0.6) : Colors.transparent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined,
                      size: 14, color: flux.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.project.name,
                      style: textTheme.bodyMedium?.copyWith(
                        color: flux.textPrimary,
                        fontWeight: widget.isSelected
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: _hovering ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 120),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: 'New chat in ${widget.project.name}',
                          child: BouncyTap(
                            onTap: () {
                              widget.onSelectProject();
                              widget.onNewChat();
                            },
                            scaleDown: 0.85,
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: Icon(Icons.edit_outlined,
                                  size: 14, color: flux.textSecondary),
                            ),
                          ),
                        ),
                        _MoreMenuButton(
                          onRename: widget.onRename,
                          onDelete: widget.onDelete,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Nested chats
        if (widget.chats.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in widget.chats)
                  _ChatRow(
                    title: c.title,
                    isSelected: c.id == widget.activeConversationId,
                    onTap: () => widget.onSelectConversation?.call(c),
                    indent: true,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A "+ New chat" button at the bottom of the project list.
class _BottomNewChatButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BottomNewChatButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    return BouncyTap(
      onTap: onTap,
      scaleDown: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: flux.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: flux.border, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 14, color: flux.textSecondary),
            const SizedBox(width: 6),
            Text(
              'New chat',
              style: textTheme.labelMedium?.copyWith(
                color: flux.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A chat conversation row. If [indent] is true, renders with extra left padding
/// to visually nest under a project.
class _ChatRow extends StatefulWidget {
  final String title;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final bool indent;

  const _ChatRow({
    required this.title,
    required this.isSelected,
    this.onTap,
    this.onRename,
    this.onDelete,
    this.indent = false,
  });

  @override
  State<_ChatRow> createState() => _ChatRowState();
}

class _ChatRowState extends State<_ChatRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;

    final bg = widget.isSelected
        ? flux.surface
        : (_hovering ? flux.surface.withValues(alpha: 0.6) : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: EdgeInsets.only(
            left: widget.indent ? 20 : 10,
            right: 10,
            top: 7,
            bottom: 7,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (widget.indent)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.chat_bubble_outline,
                      size: 13, color: flux.textTertiary),
                ),
              Expanded(
                child: Text(
                  widget.title,
                  style: textTheme.bodyMedium?.copyWith(
                    color: flux.textPrimary,
                    fontWeight: widget.isSelected
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedOpacity(
                opacity: _hovering ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: _MoreMenuButton(
                  onRename: widget.onRename,
                  onDelete: widget.onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 3-dot icon that opens a popup menu with Rename / Delete actions.
class _MoreMenuButton extends StatelessWidget {
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const _MoreMenuButton({this.onRename, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    return SizedBox(
      width: 24,
      height: 24,
      child: PopupMenuButton<String>(
        tooltip: '',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        color: flux.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: flux.border, width: 1),
        ),
        icon: Icon(Icons.more_horiz_rounded,
            size: 16, color: flux.textSecondary),
        onSelected: (v) {
          if (v == 'rename') onRename?.call();
          if (v == 'delete') onDelete?.call();
        },
        itemBuilder: (context) => [
          if (onRename != null)
            PopupMenuItem(
              value: 'rename',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.drive_file_rename_outline_rounded,
                      size: 14, color: flux.textSecondary),
                  const SizedBox(width: 8),
                  Text('Rename',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          if (onDelete != null)
            PopupMenuItem(
              value: 'delete',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded,
                      size: 14, color: flux.accentWarm),
                  const SizedBox(width: 8),
                  Text(
                    'Delete',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: flux.accentWarm),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Centered greeting shown when no messages exist in the Flux Code session.
class FluxCodeEmptyState extends StatelessWidget {
  final String projectName;
  const FluxCodeEmptyState({super.key, this.projectName = 'flux'});

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: BouncyFadeSlide(
        duration: FluxDurations.slow,
        slideOffset: 16,
        child: Text(
          'What should we build in $projectName?',
          style: textTheme.headlineSmall?.copyWith(
            color: flux.textPrimary,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// A compact chip used under the composer to expose project context,
/// execution mode, and branch.
class FluxCodeContextChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool showCaret;

  const FluxCodeContextChip({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.showCaret = true,
  });

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    return BouncyTap(
      onTap: onTap,
      scaleDown: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: flux.border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: flux.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: textTheme.labelMedium?.copyWith(
                color: flux.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (showCaret) ...[
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 14, color: flux.textTertiary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders a code block in a Cursor-like side panel — monospaced, with a
/// language tag and copy action.
class FluxCodePreviewPanel extends StatelessWidget {
  final String code;
  final String? language;
  const FluxCodePreviewPanel({super.key, required this.code, this.language});

  @override
  Widget build(BuildContext context) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: flux.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: flux.border, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: flux.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.code_rounded, size: 16, color: flux.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    (language ?? 'code').toLowerCase(),
                    style: textTheme.labelMedium?.copyWith(
                      color: flux.textSecondary,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  BouncyTap(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')),
                      );
                    },
                    child: Icon(Icons.copy_rounded,
                        size: 16, color: flux.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: SelectableText(
                  code,
                  style: GoogleFonts.firaCode(
                    fontSize: 13,
                    height: 1.6,
                    color: flux.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
