import 'package:flutter/material.dart';

import 'data/json_plan_repository.dart';
import 'data/plan_store.dart';
import 'data/sync_config.dart';
import 'ui/app.dart';

/// PlanBook 진입점.
///
/// 1단계:
/// - 앱 지원 디렉터리(`appSupport/PlanBook`)를 저장 위치로 사용.
///   단, 동기화 폴더(원드라이브 등)가 설정돼 있으면 그 폴더 아래
///   `PlanBook` 하위 폴더를 대신 사용한다([resolveDataDir]).
/// - [PlanStore] 를 생성해 디버그 화면에 주입.
/// - 라이프사이클(일시정지/종료)에서 보류 저장을 즉시 flush.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await _buildStore();
  runApp(_LifecycleFlush(store: store, child: PlanBookApp(store: store)));
}

Future<PlanStore> _buildStore() async {
  final localDir = await defaultLocalDir();
  final config = await loadSyncConfig(localDir);
  final dataDir = resolveDataDir(localDir, config);
  final repo = JsonPlanRepository(directory: dataDir);
  final store = PlanStore(repository: repo);
  return store;
}

/// 앱 라이프사이클 훅: 일시정지/비활성 시 자동 저장을 즉시 flush 한다.
class _LifecycleFlush extends StatefulWidget {
  final Widget child;
  final PlanStore store;

  const _LifecycleFlush({required this.child, required this.store});

  @override
  State<_LifecycleFlush> createState() => _LifecycleFlushState();
}

class _LifecycleFlushState extends State<_LifecycleFlush>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // 보류 중인 자동 저장을 즉시 기록.
      widget.store.flush();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
