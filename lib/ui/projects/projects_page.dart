/// Projects 화면 — 최상위 분류 목록.
///
/// 각 카드는 [computeProjectStats] 로 진행률/Task 수/지연/마감/기간을 실시간
/// 계산한다(별도 저장 없음). 카드를 누르면 Gantt 로 이동하며 그 프로젝트로
/// 필터가 자동 적용된다.
///
/// **기본 프로젝트 5개도 일반 프로젝트와 동일하게 수정/삭제 가능**하다 —
/// 삭제해도 소속 Task 는 지워지지 않고 미분류(projectId=null)가 되며, 앱을
/// 재시작해도 seed 로 다시 생기지 않는다(AppSettings.seededDefaultProjects).
library;

import 'package:flutter/material.dart';

import '../../data/plan_store.dart';
import '../../domain/plan_filter.dart';
import '../../domain/project.dart';
import '../../domain/project_stats.dart';
import '../common/dialog_insets.dart';
import '../common/navigation.dart';

class ProjectsPage extends StatefulWidget {
  final PlanStore store;
  final OpenInGantt? onOpenInGantt;

  const ProjectsPage({super.key, required this.store, this.onOpenInGantt});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  PlanStore get _store => widget.store;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    if (!_store.isLoaded) _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _openProjectInGantt(Project p) {
    widget.onOpenInGantt?.call(filter: PlanFilterState(projectIds: {p.id}));
  }

  Future<void> _createProject() async {
    final result = await _showEditDialog(context, name: '', color: 0xFF6750A4);
    if (result == null) return;
    _store.createProject(result.name, color: result.color);
  }

  Future<void> _editProject(Project p) async {
    final result =
        await _showEditDialog(context, name: p.name, color: p.color);
    if (result == null) return;
    _store.updateProject(p.id, (cur) =>
        cur.copyWith(name: result.name, color: result.color));
  }

  Future<void> _deleteProject(Project p) async {
    final count = _store.tree.allNodes.where((n) => n.projectId == p.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: safeDialogInsetPadding(ctx),
        title: const Text('프로젝트 삭제'),
        content: Text(
          count > 0
              ? '"${p.name}" 프로젝트를 삭제합니다.\n'
                  '소속된 Task $count개는 삭제되지 않고 "미분류" 로 남습니다.'
              : '"${p.name}" 프로젝트를 삭제합니다.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (confirmed != true) return;
    _store.deleteProject(p.id);
  }

  void _toggleArchive(Project p) {
    _store.updateProject(p.id, (cur) => cur.copyWith(isArchived: !cur.isArchived));
  }

  @override
  Widget build(BuildContext context) {
    if (!_store.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final all = _store.projects; // 이미 sortOrder 순.
    final active = all.where((p) => !p.isArchived).toList();
    final archived = all.where((p) => p.isArchived).toList();
    final today = _store.today;

    return Scaffold(
      appBar: AppBar(
        title: const Text('프로젝트'),
        actions: [
          if (archived.isNotEmpty)
            IconButton(
              tooltip: _showArchived ? '보관된 프로젝트 숨기기' : '보관된 프로젝트 보기',
              onPressed: () => setState(() => _showArchived = !_showArchived),
              icon: Icon(_showArchived ? Icons.archive : Icons.archive_outlined),
            ),
          IconButton(
            tooltip: '프로젝트 추가',
            onPressed: _createProject,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: all.isEmpty
          ? const Center(child: Text('프로젝트가 없습니다.'))
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: active.length,
              onReorderItem: (oldIndex, newIndex) {
                final ids = active.map((p) => p.id).toList();
                final id = ids.removeAt(oldIndex);
                ids.insert(newIndex, id);
                _store.reorderProjects(ids);
              },
              itemBuilder: (context, i) {
                final p = active[i];
                final stats = computeProjectStats(_store.tree, p.id, today);
                return _ProjectCard(
                  key: ValueKey(p.id),
                  project: p,
                  stats: stats,
                  onTap: () => _openProjectInGantt(p),
                  onEdit: () => _editProject(p),
                  onDelete: () => _deleteProject(p),
                  onArchive: () => _toggleArchive(p),
                );
              },
              footer: _showArchived && archived.isNotEmpty
                  ? Column(
                      key: const ValueKey('archived-section'),
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(),
                        ),
                        for (final p in archived)
                          Opacity(
                            opacity: 0.6,
                            child: _ProjectCard(
                              project: p,
                              stats: computeProjectStats(_store.tree, p.id, today),
                              onTap: () => _openProjectInGantt(p),
                              onEdit: () => _editProject(p),
                              onDelete: () => _deleteProject(p),
                              onArchive: () => _toggleArchive(p),
                            ),
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
    );
  }
}

class _ProjectEditResult {
  final String name;
  final int color;
  const _ProjectEditResult(this.name, this.color);
}

const List<int> _kColorPalette = [
  0xFF3F6DE0,
  0xFF00897B,
  0xFFE0663F,
  0xFF8E5BD0,
  0xFF6B7280,
  0xFFD81B60,
  0xFFFFB300,
  0xFF43A047,
];

Future<_ProjectEditResult?> _showEditDialog(
  BuildContext context, {
  required String name,
  required int color,
}) {
  final ctrl = TextEditingController(text: name);
  int selectedColor = color;
  return showDialog<_ProjectEditResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        insetPadding: safeDialogInsetPadding(ctx),
        title: Text(name.isEmpty ? '프로젝트 추가' : '프로젝트 편집'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '이름',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('색상'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final c in _kColorPalette)
                  GestureDetector(
                    onTap: () => setState(() => selectedColor = c),
                    child: CircleAvatar(
                      backgroundColor: Color(c),
                      radius: 14,
                      child: selectedColor == c
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final n = ctrl.text.trim();
              Navigator.of(ctx).pop(
                _ProjectEditResult(n.isEmpty ? '(이름 없음)' : n, selectedColor),
              );
            },
            child: const Text('저장'),
          ),
        ],
      ),
    ),
  );
}

class _ProjectCard extends StatelessWidget {
  final Project project;
  final ProjectStats stats;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onArchive;

  const _ProjectCard({
    super.key,
    required this.project,
    required this.stats,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(backgroundColor: Color(project.color), radius: 8),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      project.isArchived ? '${project.name} (보관됨)' : project.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'edit':
                          onEdit();
                          break;
                        case 'archive':
                          onArchive();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'edit', child: Text('이름/색상 변경')),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(project.isArchived ? '보관 해제' : 'Archive'),
                      ),
                      const PopupMenuItem(value: 'delete', child: Text('삭제')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: stats.progress,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: Color(project.color),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _stat(context, '전체', '${stats.total}'),
                  _stat(context, '완료', '${stats.done}'),
                  _stat(context, '미완료', '${stats.incomplete}'),
                  if (stats.overdue > 0)
                    _stat(context, '지연', '${stats.overdue}', color: scheme.error),
                ],
              ),
              if (stats.nearestDeadline != null || stats.periodStart != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    [
                      if (stats.nearestDeadline != null)
                        '가까운 마감: ${stats.nearestDeadline!.toIso()}',
                      if (stats.periodStart != null && stats.periodEnd != null)
                        '기간: ${stats.periodStart!.toIso()} ~ ${stats.periodEnd!.toIso()}',
                    ].join('   '),
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value, {Color? color}) {
    return Text(
      '$label $value',
      style: TextStyle(
        fontSize: 12,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: color != null ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}
