import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'data/json_plan_repository.dart';
import 'data/plan_store.dart';
import 'data/sync_config.dart';
import 'ui/app.dart';

/// PlanBook 진입점.
///
/// - 앱 지원 디렉터리(`appSupport/PlanBook`)를 저장 위치로 사용.
///   단, 동기화 폴더가 설정돼 있으면 그 폴더 아래를 대신 사용한다.
/// - [PlanStore] 를 생성해 화면에 주입.
/// - **창을 닫을 때 저장이 끝날 때까지 종료를 미룬다**([_LifecycleFlush]).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await _buildStore();
  runApp(_LifecycleFlush(
    store: store,
    child: PlanBookApp(
      store: store,
      navigatorKey: _LifecycleFlushState.navigatorKey,
    ),
  ));
}

Future<PlanStore> _buildStore() async {
  final localDir = await defaultLocalDir();
  final config = await loadSyncConfig(localDir);
  final dataDir = resolveDataDir(localDir, config);
  final repo = JsonPlanRepository(directory: dataDir);
  final store = PlanStore(repository: repo);
  return store;
}

/// 종료/백그라운드 진입 시 보류 중인 자동 저장을 확실히 기록한다.
///
/// **왜 [AppLifecycleListener.onExitRequested] 인가**: 예전에는
/// `didChangeAppLifecycleState` 에서 `store.flush()` 를 호출하되 **await 하지
/// 않았다**. 모바일에서는 프로세스가 살아있어 결국 저장이 끝나지만, Windows
/// 에서 창 X 를 누르면 그 비동기 파일 쓰기가 끝나기 전에 프로세스가 종료되어
/// **작성한 내용이 통째로 사라졌다.**
///
/// [onExitRequested] 는 OS 가 종료를 요청했을 때 프레임워크가 불러주는 훅으로,
/// **비동기 작업을 끝낼 때까지 종료를 붙잡아 둘 수 있고** 필요하면 취소까지
/// 할 수 있다. 저장이 실패하면 조용히 닫지 않고 사용자에게 물어본다 —
/// 저장 실패를 알리지 않고 종료하는 것이 가장 나쁜 결말이다.
class _LifecycleFlush extends StatefulWidget {
  final Widget child;
  final PlanStore store;

  const _LifecycleFlush({required this.child, required this.store});

  @override
  State<_LifecycleFlush> createState() => _LifecycleFlushState();
}

class _LifecycleFlushState extends State<_LifecycleFlush> {
  late final AppLifecycleListener _listener;

  /// 저장 실패를 알리는 다이얼로그를 위젯 트리 밖에서 띄우기 위한 키.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
      onStateChange: _onStateChange,
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  /// 모바일에서 백그라운드로 갈 때의 저장. 여기서는 프로세스가 곧바로 죽지
  /// 않으므로 await 하지 않아도 저장이 완료된다.
  void _onStateChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.store.flush();
    }
  }

  /// 창을 닫으려 할 때. **저장이 끝날 때까지 기다린 뒤** 종료를 허용한다.
  Future<AppExitResponse> _onExitRequested() async {
    final saved = await widget.store.flush();
    if (saved) return AppExitResponse.exit;

    // 저장 실패 — 그냥 닫으면 작성한 내용이 사라진다. 사용자에게 알린다.
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      // 다이얼로그를 띄울 수 없는 상황이면 데이터를 지키는 쪽(종료 취소)을 고른다.
      return AppExitResponse.cancel;
    }
    final quitAnyway = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: const Text('저장하지 못했습니다'),
        content: Text(
          '변경 내용을 저장하는 데 실패했습니다.\n'
          '지금 닫으면 저장되지 않은 내용이 사라집니다.\n\n'
          '사유: ${widget.store.lastSaveError}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('닫지 않기'),
          ),
          TextButton(
            onPressed: () async {
              // 한 번 더 시도해 보고, 되면 그대로 닫는다.
              final retried = await widget.store.flush();
              if (dctx.mounted) Navigator.of(dctx).pop(retried);
            },
            child: const Text('다시 저장 시도'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('저장하지 않고 닫기'),
          ),
        ],
      ),
    );
    return quitAnyway == true ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
