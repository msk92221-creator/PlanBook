/// 앱 설정 화면.
///
/// [AppSettings] 를 [PlanStore.updateSettings] 단일 경로로만 변경한다(별도
/// 저장 경로를 만들지 않는다). 앱 기본 진입 화면은 항상 Today 이고, "마지막
/// 화면 복원"은 이 화면에서 켤 수 있는 선택 기능이다.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/plan_export_import.dart';
import '../../data/plan_store.dart';
import '../../domain/app_settings.dart';
import '../../domain/plan_integrity.dart';
import '../plan/gantt_metrics.dart';

class SettingsPage extends StatelessWidget {
  final PlanStore store;

  const SettingsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = store.settings;
        return Scaffold(
          appBar: AppBar(title: const Text('설정')),
          body: ListView(
            children: [
              const _SectionHeader('화면'),
              ListTile(
                title: const Text('테마'),
                subtitle: Text(_themeLabel(s.themeMode)),
                trailing: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('시스템')),
                    ButtonSegment(value: ThemeMode.light, label: Text('라이트')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('다크')),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => store
                      .updateSettings((cur) => cur.copyWith(themeMode: v.first)),
                ),
              ),
              SwitchListTile(
                title: const Text('마지막 화면 복원'),
                subtitle: const Text('꺼져 있으면 앱을 열 때마다 항상 "오늘" 화면으로 시작합니다.'),
                value: s.restoreLastScreen,
                onChanged: (v) => store
                    .updateSettings((cur) => cur.copyWith(restoreLastScreen: v)),
              ),
              const Divider(),
              const _SectionHeader('Gantt'),
              ListTile(
                title: const Text('기본 줌'),
                subtitle: const Text('Gantt 화면을 열 때 처음 적용되는 확대 수준입니다.'),
                trailing: SegmentedButton<GanttZoomLevel>(
                  segments: [
                    for (final z in GanttZoomLevel.values)
                      ButtonSegment(value: z, label: Text(z.label)),
                  ],
                  selected: {s.defaultZoom},
                  onSelectionChanged: (v) => store
                      .updateSettings((cur) => cur.copyWith(defaultZoom: v.first)),
                ),
              ),
              const Divider(),
              const _SectionHeader('달력'),
              ListTile(
                title: const Text('주 시작 요일'),
                subtitle: const Text('달력/이번 주 필터 등에서 한 주의 시작으로 쓰입니다.'),
                trailing: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: DateTime.monday, label: Text('월요일')),
                    ButtonSegment(value: DateTime.sunday, label: Text('일요일')),
                  ],
                  selected: {s.weekStart},
                  onSelectionChanged: (v) => store
                      .updateSettings((cur) => cur.copyWith(weekStart: v.first)),
                ),
              ),
              const Divider(),
              const _SectionHeader('백업'),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('내보내기'),
                subtitle: const Text('현재 데이터를 JSON 파일로 저장합니다. 저장 후 표시되는 '
                    '경로에서 파일을 원하는 곳(OneDrive 폴더 등)으로 옮길 수 있습니다.'),
                onTap: () => _export(context),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('가져오기'),
                subtitle: const Text('백업 파일 경로를 입력해 불러옵니다. '
                    '가져오면 현재 데이터가 모두 대체됩니다.'),
                onTap: () => _importFlow(context),
              ),
              if (kDebugMode) ...[
                const Divider(),
                const _SectionHeader('디버그'),
                ListTile(
                  leading: const Icon(Icons.health_and_safety_outlined),
                  title: const Text('데이터 무결성 검사'),
                  subtitle: const Text(
                      'id 중복/끊긴 참조/순환 참조 등을 점검합니다(디버그 빌드 전용).'),
                  onTap: () => _runIntegrityCheck(context),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _runIntegrityCheck(BuildContext context) {
    final report = checkIntegrity(
      nodes: store.tree.allNodes,
      projects: store.projects,
      tags: store.tags,
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(report.isClean ? '이상 없음' : '문제 ${report.issues.length}건 발견'),
        content: SizedBox(
          width: 400,
          child: report.isClean
              ? const Text('id 중복/끊긴 참조/순환 참조 등 검사한 항목에서 문제를 찾지 못했습니다.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final issue in report.issues)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '[${issue.severity == IntegritySeverity.error ? '오류' : '주의'}] ${issue.message}',
                            style: TextStyle(
                              fontSize: 12,
                              color: issue.severity == IntegritySeverity.error
                                  ? Theme.of(ctx).colorScheme.error
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode m) => switch (m) {
        ThemeMode.system => '시스템 설정을 따름',
        ThemeMode.light => '라이트',
        ThemeMode.dark => '다크',
      };

  Future<void> _export(BuildContext context) async {
    final docs = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    String pad2(int n) => n.toString().padLeft(2, '0');
    final fileName = 'planbook_backup_${now.year}${pad2(now.month)}${pad2(now.day)}'
        '_${pad2(now.hour)}${pad2(now.minute)}${pad2(now.second)}.json';
    final file = File('${docs.path}${Platform.pathSeparator}$fileName');
    await exportSnapshotToFile(store.exportableSnapshot(), file);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('내보내기 완료'),
        content: SelectableText(file.path),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: file.path));
              Navigator.of(ctx).pop();
            },
            child: const Text('경로 복사'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _importFlow(BuildContext context) async {
    final pathCtrl = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('가져오기'),
        content: TextField(
          controller: pathCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '백업 파일 경로',
            hintText: r'C:\Users\...\planbook_backup_....json',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(pathCtrl.text.trim()),
            child: const Text('불러오기'),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty) return;

    final result = await readAndParseImportFile(File(path));
    if (!context.mounted) return;
    if (!result.isSuccess) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('가져오기 실패'),
          content: Text(result.error!),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }

    final snapshot = result.snapshot!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('덮어쓰기 확인'),
        content: Text(
          '이 파일에는 작업 ${snapshot.nodes.length}개, '
          '프로젝트 ${snapshot.projects.length}개가 들어 있습니다.\n'
          '지금 가져오면 현재 앱의 모든 데이터가 이 내용으로 바뀝니다. 계속할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('덮어쓰기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await store.importSnapshot(snapshot);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
