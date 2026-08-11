/// 앱 설정 화면.
///
/// [AppSettings] 를 [PlanStore.updateSettings] 단일 경로로만 변경한다(별도
/// 저장 경로를 만들지 않는다). 앱 기본 진입 화면은 항상 Today 이고, "마지막
/// 화면 복원"은 이 화면에서 켤 수 있는 선택 기능이다.
///
/// 동기화(OneDrive) 상태만은 예외로 [PlanStore] 밖에 있다 — 로그인 여부와
/// 마지막 동기화 시각은 기기마다 다른 값이라 동기화되는 데이터에 넣지 않는다.
/// 그래서 이 화면은 [StatefulWidget] 으로 그 값을 따로 로드/보관한다.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_dirs.dart';
import '../../data/plan_export_import.dart';
import '../../data/plan_store.dart';
import '../../data/sync/graph_client.dart';
import '../../data/sync/onedrive_auth.dart';
import '../../data/sync/sync_decision.dart';
import '../../data/sync/sync_service.dart';
import '../../data/sync/sync_state.dart';
import '../../data/update_check.dart';
import '../../domain/app_settings.dart';
import '../../domain/plan_integrity.dart';
import '../plan/gantt_metrics.dart';

/// GitHub 저장소(owner/repo) — 업데이트 확인이 조회할 대상.
const String kUpdateRepoOwner = 'msk92221-creator';
const String kUpdateRepoName = 'PlanBook';

class SettingsPage extends StatefulWidget {
  final PlanStore store;

  const SettingsPage({super.key, required this.store});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  PlanStore get store => widget.store;

  Directory? _localDir;
  OneDriveAuth? _auth;

  /// 로그인 여부. 조회 전에는 false 로 두고, 확인되면 갱신한다 —
  /// 로딩 스피너를 두지 않는 이유는 끝없이 도는 애니메이션이 위젯 테스트의
  /// pumpAndSettle 을 무한 대기시키기 때문이다.
  bool _signedIn = false;
  SyncState _syncState = SyncState.never;

  /// 동기화가 진행 중인 동안 버튼을 잠그기 위한 플래그.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
  }

  /// path_provider / 보안 저장소는 플랫폼 채널을 타므로, 채널이 없는 환경
  /// (위젯 테스트 등)에서도 화면이 죽지 않아야 한다 — 실패하면 로그아웃
  /// 상태로 둔다.
  Future<void> _loadSyncStatus() async {
    try {
      final localDir = await defaultLocalDir();
      final auth = OneDriveAuth();
      final signedIn = await auth.isSignedIn;
      final state = await loadSyncState(localDir);
      if (!mounted) return;
      setState(() {
        _localDir = localDir;
        _auth = auth;
        _signedIn = signedIn;
        _syncState = state;
      });
    } catch (_) {
      // 기본값(로그아웃)이 이미 안전한 상태다.
    }
  }

  SyncService? _buildService() {
    final auth = _auth;
    final dir = _localDir;
    if (auth == null || dir == null) return null;
    return SyncService(
      store: store,
      graph: GraphClient(accessToken: auth.accessToken),
      localDir: dir,
    );
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
  /// "동기화" 섹션. 계정 로그인 / 지금 동기화 / 마지막 동기화 시각.
  Widget _buildSyncSection(BuildContext context) {
    if (!isOneDriveConfigured) {
      return const ListTile(
        leading: Icon(Icons.cloud_off_outlined),
        title: Text('동기화를 쓸 수 없습니다'),
        subtitle: Text('이 빌드에는 OneDrive 클라이언트 ID 가 설정되지 않았습니다.'),
      );
    }

    final last = _syncState.lastSyncedAt;
    return Column(
      children: [
        ListTile(
          leading: Icon(_signedIn ? Icons.cloud_done_outlined : Icons.cloud_outlined),
          title: Text(_signedIn ? 'OneDrive 연결됨' : 'OneDrive 계정 연결'),
          subtitle: Text(
            _signedIn
                ? '계획 데이터가 OneDrive 앱 폴더에 저장됩니다. '
                    '다른 기기에서도 같은 계정으로 로그인하면 같은 데이터를 씁니다.'
                : 'Microsoft 계정으로 로그인하면 Windows/Android 사이에서 '
                    '계획을 주고받을 수 있습니다.',
          ),
          isThreeLine: true,
          trailing: _signedIn
              ? TextButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text('연결 해제'),
                )
              : FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: const Text('로그인'),
                ),
        ),
        if (_signedIn)
          ListTile(
            leading: _busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : const Icon(Icons.sync),
            title: const Text('지금 동기화'),
            subtitle: Text(
              last == null
                  ? '아직 동기화한 적이 없습니다.'
                  : '마지막 동기화: ${_formatTime(last)}',
            ),
            onTap: _busy ? null : _syncNow,
          ),
      ],
    );
  }

  String _formatTime(DateTime t) {
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p2(t.month)}-${p2(t.day)} ${p2(t.hour)}:${p2(t.minute)}';
  }

  Future<void> _signIn() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final auth = _auth ?? OneDriveAuth();
      await auth.signIn();
      if (!mounted) return;
      setState(() {
        _auth = auth;
        _signedIn = true;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('OneDrive 에 연결되었습니다. 이제 동기화할 수 있습니다.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('로그인 실패: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('연결 해제'),
        content: const Text(
            'OneDrive 연결을 끊습니다. 이 기기의 계획 데이터는 그대로 남고, '
            'OneDrive 에 올라간 내용도 지워지지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('연결 해제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await (_auth ?? OneDriveAuth()).signOut();
    if (!mounted) return;
    setState(() => _signedIn = false);
    messenger.showSnackBar(
      const SnackBar(content: Text('연결이 해제되었습니다.')),
    );
  }

  Future<void> _syncNow() async {
    final messenger = ScaffoldMessenger.of(context);
    final svc = _buildService();
    if (svc == null) return;

    setState(() => _busy = true);
    try {
      final result = await svc.sync();
      if (!mounted) return;

      if (result.outcome == SyncOutcome.conflict) {
        await _resolveConflict(svc, result);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(switch (result.outcome) {
          SyncOutcome.upToDate => '이미 최신 상태입니다.',
          SyncOutcome.uploaded => '이 기기 내용을 OneDrive 에 올렸습니다.',
          SyncOutcome.downloaded => 'OneDrive 의 최신 내용을 받아왔습니다.',
          SyncOutcome.conflict => '',
        })));
      }
      await _refreshSyncState();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('동기화 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 충돌 — **자동으로 한쪽을 버리지 않는다.** 사용자가 고르게 하고, 어느
  /// 쪽을 고르든 버려지는 쪽은 백업 파일로 남는다([SyncService.resolveConflict]).
  Future<void> _resolveConflict(SyncService svc, SyncResult result) async {
    final messenger = ScaffoldMessenger.of(context);
    final localCount = store.tree.allNodes.length;
    final remoteCount = result.remoteSnapshot?.nodes.length;

    final choice = await showDialog<ConflictResolution>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('양쪽이 모두 바뀌었습니다'),
        content: Text(
          '이 기기와 OneDrive 양쪽에서 각각 내용이 바뀌어 자동으로 합칠 수 없습니다.\n\n'
          '• 이 기기: 작업 $localCount개\n'
          '• OneDrive: 작업 ${remoteCount ?? '?'}개\n\n'
          '어느 쪽을 남길까요? 선택하지 않은 쪽은 이 기기에 백업 파일로 저장됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('나중에'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(ConflictResolution.keepRemote),
            child: const Text('OneDrive 것 사용'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(ConflictResolution.keepLocal),
            child: const Text('이 기기 것 사용'),
          ),
        ],
      ),
    );
    if (choice == null) return;

    final outcome = await svc.resolveConflict(choice);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(outcome == SyncOutcome.uploaded
          ? '이 기기 내용으로 맞췄습니다.'
          : 'OneDrive 내용으로 맞췄습니다.'),
    ));
  }

  Future<void> _refreshSyncState() async {
    final dir = _localDir;
    if (dir == null) return;
    final state = await loadSyncState(dir);
    if (!mounted) return;
    setState(() => _syncState = state);
  }


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
