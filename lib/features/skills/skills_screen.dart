import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/skill_provider.dart';
import '../../core/theme/flux_theme.dart';
import '../../core/widgets/flux_widgets.dart';
import '../../core/widgets/flux_animations.dart';

class SkillsScreen extends ConsumerWidget {
  const SkillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(skillProvider);
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: flux.background,
      body: FluxDottedBackground(
        child: Stack(
          children: [
            Positioned(
              left: 20,
              top: topPadding + 48,
              child: FluxBackButton(onTap: () => context.pop()),
            ),
            Positioned(
              left: 20,
              top: topPadding + 100,
              child: const FluxTitle(
                title: "Skills",
                subtitle: "Capabilities Flux can use during chat",
              ),
            ),
            Positioned.fill(
              top: topPadding + 180,
              left: 20,
              right: 20,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: skills.length,
                itemBuilder: (context, index) {
                  final skill = skills[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _SkillTile(skill: skill),
                  );
                },
              ),
            ),

            // Create Skill FAB
            Positioned(
              right: 24,
              bottom: 40 + MediaQuery.of(context).padding.bottom,
              child: BouncyTap(
                onTap: () => _showCreateSkillDialog(context, ref),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: flux.textPrimary,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: flux.textPrimary.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(Icons.add_rounded, color: flux.background, size: 32),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateSkillDialog(BuildContext context, WidgetRef ref) {
    // Basic dialog for now, can be expanded to a full screen later
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: flux.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text("Create New Skill"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(hintText: "Skill Name (e.g. Weather)"),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(hintText: "Description (How to use it)"),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                // In a real app, we'd save this to Hive. For now, we update the provider.
                ref.read(skillProvider.notifier).addSkill(
                  Skill(
                    id: nameController.text.toLowerCase().replaceAll(' ', '_'),
                    name: nameController.text,
                    description: descController.text,
                  ),
                );
                Navigator.pop(context);
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }
}

class _SkillTile extends ConsumerWidget {
  final Skill skill;
  const _SkillTile({required this.skill});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flux = Theme.of(context).extension<FluxColorsExtension>()!;
    final textTheme = Theme.of(context).textTheme;

    return BouncyTap(
      onTap: () {
        HapticFeedback.lightImpact();
        ref.read(skillProvider.notifier).toggleSkill(skill.id);
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: flux.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: skill.isEnabled ? flux.textPrimary : flux.border,
            width: skill.isEnabled ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (skill.isEnabled)
              BoxShadow(
                color: flux.textPrimary.withValues(alpha: 0.05),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: skill.isEnabled ? flux.textPrimary : flux.border.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getIconForSkill(skill.id),
                color: skill.isEnabled ? flux.background : flux.textSecondary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skill.name,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    skill.description,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: skill.isEnabled,
              activeTrackColor: flux.textPrimary,
              onChanged: (_) {
                HapticFeedback.lightImpact();
                ref.read(skillProvider.notifier).toggleSkill(skill.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForSkill(String id) {
    switch (id) {
      case 'web_search': return Icons.search_rounded;
      case 'creations': return Icons.auto_awesome_mosaic_rounded;
      default: return Icons.extension_rounded;
    }
  }
}
