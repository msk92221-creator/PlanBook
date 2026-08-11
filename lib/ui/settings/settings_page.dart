/// 앱 설정 화면.
///
/// [AppSettings] 를 [PlanStore.updateSettings] 단일 경로로만 변경한다(별도
/// 저장 경로를 만들지 않는다). 앱 기본 진입 화면은 항상 Today 이고, "마지막
/// 화면 복원"은 이 화면에서 켤 수 있는 선택 기능이다.
///
/// 동기화 설정([SyncConfig])만은 예외로, [PlanStore]가 들고 있는 데이터가
/// 아니라 기기 로컬 전용 파일에 별도로 저장된다(왜인지는
/// data/sync_config.dart 문서 참고). 그래서 이 화면은 [StatefulWidget]으로
/// 그 값을 따로 로드/보관한다.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/json_plan_repository.dart';
import '../../data/plan_export_import.dart';
import '../../data/plan_store.dart';
import '../../data/sync_config.dart';
import '../../data/update_check.dart';
import '../../domain/app_settings.dart';
import '../../domain/plan_integrity.dart';
import '../plan/gantt_metrics.dart';

/// GitHub 저장소(owner/repo) — 업데이트 확인이 조회할 대상.
const String kUpdateRepoOwner = 'msk92221-creator';
const String kUpdateRepoName = 'PlanBook';

/// 동기화 폴더 선택 시, 이미 데이터가 있는 폴더를 발견하면 사용자에게 묻는
/// 세 가지 선택지.
enum _SyncFolderChoice { cancel, useFolder, overwriteFolder }

class SettingsPage extends StatefulWidget {
  final PlanStore store;

  const SettingsPage({super.key, required this.store});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  PlanStore get store => widget.store;

  Directory? _localDir;

  /// 동기화 설정 로드 전 기본값은 "꺼짐"이다 — 로딩 스피너를 따로 두지
  /// 않는다. 실제 기기에서는 [defaultLocalDir]가 거의 즉시 응답하므로 켜져
  /// 있는 경우에도 잠깐 깜빡이는 정도이고, path_provider 채널이 없는 환경
  /// (위젯 테스트 등)에서도 화면이 "로딩 중" 애니메이션에 영구히 묶이지
  /// 않는다(끝없이 도는 스피너는 pumpAndSettle 을 무한 대기시킨다).
  SyncConfig _syncConfig = const SyncConfig();

  @override
  void initState() {
    super.initState();
    _loadSyncConfig();
  }

  Future<void> _loadSyncConfig() async {
    try {
      final localDir = await defaultLocalDir();
      final config = await loadSyncConfig(localDir);
      if (!mounted) return;
      setState(() {
        _localDir = localDir;
        _syncConfig = config;
      });
    } catch (_) {
      // 조회 실패 시 이미 기본값(동기화 꺼짐)이므로 할 일 없음.
    }
  }

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
              const _SectionHeader('동기화'),
              _buildSyncSection(context),
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
              const Divider(),
              const _SectionHeader('앱 정보'),
              ListTile(
                leading: const Icon(Icons.system_update_alt_outlined),
                title: const Text('업데이트 확인'),
                subtitle: Text('GitHub 릴리스($kUpdateRepoOwner/$kUpdateRepoName)에서 '
                    '새 버전이 있는지 확인합니다.'),
                onTap: () => _checkUpdate(context),
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

  /// "동기화" 섹션 본문. 설정 로드 전에는 진행 표시만 보여준다.
  Widget _buildSyncSection(BuildContext context) {
    final config = _syncConfig;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_sync_outlined),
          title: const Text('동기화 폴더 (OneDrive 등)'),
          subtitle: Text(
            config.isEnabled
                ? '${config.folderPath}${Platform.pathSeparator}PlanBook\n'
                    '다른 폴더로 바꾸려면 다시 선택하세요. '
                    '적용하려면 앱을 재시작해야 합니다.'
                : '설정 안 함 — 이 기기에만 저장됩니다.\n'
                    'OneDrive 등 동기화 폴더를 지정하면, 그 폴더를 통해 다른 기기와 '
                    '같은 데이터를 공유할 수 있습니다.',
          ),
          isThreeLine: true,
          onTap: () => _pickSyncFolder(context),
        ),
        if (config.isEnabled)
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text('동기화 해제'),
            subtitle: const Text('현재 데이터를 이 기기 로컬 저장 위치로 복사한 뒤 폴더 연결을 끊습니다.'),
            onTap: () => _disableSync(context),
          ),
      ],
    );
  }

  Future<void> _pickSyncFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await getDirectoryPath(
      confirmButtonText: '이 폴더로 동기화',
    );
    if (picked == null || picked.isEmpty) return;
    if (!context.mounted) return;

    final targetDir = syncDataDir(picked);
    final existing = await JsonPlanRepository(directory: targetDir).load();
    if (!context.mounted) return;

    if (existing != null) {
      final choice = await showDialog<_SyncFolderChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('이미 데이터가 있는 폴더입니다'),
          content: Text(
            '선택한 폴더에 작업 ${existing.nodes.length}개, '
            '프로젝트 ${existing.projects.length}개가 들어 있는 PlanBook 데이터가 이미 '
            '있습니다.\n\n어떻게 할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_SyncFolderChoice.cancel),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_SyncFolderChoice.overwriteFolder),
              child: const Text('현재 기기 데이터로 덮어쓰기'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_SyncFolderChoice.useFolder),
              child: const Text('폴더 데이터 사용'),
            ),
          ],
        ),
      );
      if (choice == null || choice == _SyncFolderChoice.cancel) return;
      if (choice == _SyncFolderChoice.overwriteFolder) {
        await JsonPlanRepository(directory: targetDir)
            .save(store.exportableSnapshot());
      }
      // useFolder: 폴더에 이미 있는 데이터를 그대로 둔다. 재시작 시 그 데이터로 열린다.
    } else {
      // 빈 폴더면 현재 데이터를 그대로 복사해 둔다(전환 과정에서 데이터 유실 방지).
      await JsonPlanRepository(directory: targetDir)
          .save(store.exportableSnapshot());
    }

    final localDir = _localDir ?? await defaultLocalDir();
    final newConfig = SyncConfig(folderPath: picked);
    await saveSyncConfig(localDir, newConfig);
    if (!mounted) return;
    setState(() {
      _localDir = localDir;
      _syncConfig = newConfig;
    });
    messenger.showSnackBar(
      const SnackBar(content: Text('동기화 폴더가 설정되었습니다. 적용하려면 앱을 재시작하세요.')),
    );
  }

  Future<void> _disableSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('동기화 해제'),
        content: const Text(
            '현재 데이터를 이 기기의 로컬 저장 위치로 복사한 뒤 동기화 폴더 연결을 끊습니다. 계속할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('해제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final localDir = _localDir ?? await defaultLocalDir();
    await JsonPlanRepository(directory: localDir)
        .save(store.exportableSnapshot());
    await saveSyncConfig(localDir, const SyncConfig());
    if (!mounted) return;
    setState(() {
      _localDir = localDir;
      _syncConfig = const SyncConfig();
    });
    messenger.showSnackBar(
      const SnackBar(content: Text('동기화가 해제되었습니다. 적용하려면 앱을 재시작하세요.')),
    );
  }

  /// GitHub 최신 릴리스를 확인하고, 더 새 버전이 있으면 다운로드 여부를 묻는다.
  /// **자동으로 다운로드/설치하지 않는다** — 항상 사용자가 "다운로드"를
  /// 눌러야 브라우저/OS 다운로드 관리자가 파일을 받는다.
  Future<void> _checkUpdate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final info = await PackageInfo.fromPlatform();
    final release =
        await fetchLatestRelease(owner: kUpdateRepoOwner, repo: kUpdateRepoName);
    if (!context.mounted) return;

    if (release == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('업데이트 확인에 실패했습니다. 네트워크를 확인해주세요.')),
      );
      return;
    }
    if (!isNewerVersion(info.version, release.tagName)) {
      messenger.showSnackBar(
        SnackBar(content: Text('이미 최신 버전입니다 (${info.version}).')),
      );
      return;
    }

    final asset =
        pickAssetForPlatform(release, isAndroid: Platform.isAndroid);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('새 버전 ${release.tagName} 있음'),
        content: Text(
          '현재 버전: ${info.version}\n최신 버전: ${release.tagName}\n\n'
          '${asset != null ? '다운로드를 누르면 브라우저/다운로드 관리자로 파일을 받습니다.' : '이 플랫폼용 첨부 파일을 찾지 못해 릴리스 페이지로 이동합니다.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('나중에'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(
                Uri.parse(asset?.downloadUrl ?? release.htmlUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('다운로드'),
          ),
        ],
      ),
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
