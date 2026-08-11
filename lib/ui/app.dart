import 'package:flutter/material.dart';

import '../data/plan_store.dart';
import 'app_shell.dart';

/// PlanBook 최상위 위젯.
///
/// 메인 화면은 [AppShell] — Today / Gantt / Calendar / Projects 4개 화면을 묶는다.
/// 기본 진입 화면은 Today 이며, 테마는 [AppSettings.themeMode] 를 따른다.
class PlanBookApp extends StatelessWidget {
  final PlanStore store;

  /// 위젯 트리 밖(앱 종료 훅 등)에서 다이얼로그를 띄우기 위한 키.
  final GlobalKey<NavigatorState>? navigatorKey;

  const PlanBookApp({super.key, required this.store, this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    // 설정(themeMode)이 바뀌면 테마를 다시 적용해야 하므로 store 를 구독한다.
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => MaterialApp(
        title: 'PlanBook',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF2E5BB6),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF2E5BB6),
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: store.settings.themeMode,
        home: AppShell(store: store),
      ),
    );
  }
}
