/// 4개 화면(Today / Gantt / Calendar / Projects)을 묶는 최상위 네비게이션 셸.
///
/// 규칙:
/// - **앱 기본 진입 화면은 Today** 다. 저장된 [AppSettings.lastScreen] 이 있으면
///   재실행 시 그 화면을 복원하되, 값이 없을 때의 기본값은 항상 Today.
/// - 넓은 화면(>= [kTwoPaneBreakpoint]) 은 좌측 [NavigationRail],
///   좁은 화면은 하단 [NavigationBar]. (Gantt 폭을 최대한 확보하기 위함)
/// - 화면 전환 시 각 화면 상태를 보존한다([IndexedStack]).
/// - **화면 간 이동**: Today/Calendar/Projects 에서 "Gantt 에서 보기" 를 선택하면
///   이 셸이 Gantt 탭으로 전환하면서 필터/포커스 대상을 [PlanPage] 에 주입한다.
///   각 화면이 직접 Navigator 를 쓰지 않고, 이 콜백 하나로 통일한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/plan_store.dart';
import '../domain/app_settings.dart';
import '../domain/plan_filter.dart';
import 'calendar/calendar_page.dart';
import 'plan/gantt_theme.dart';
import 'plan/plan_page.dart';
import 'projects/projects_page.dart';
import 'search/search_page.dart';
import 'today/today_page.dart';

class AppShell extends StatefulWidget {
  final PlanStore store;

  const AppShell({super.key, required this.store});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppScreen _current;

  /// Gantt 진입 시 적용할 필터/포커스 대상(다른 화면에서 넘어올 때 설정됨).
  PlanFilterState? _ganttFilter;
  String? _ganttFocusNodeId;

  @override
  void initState() {
    super.initState();
    // 정책: 앱 기본 진입 화면은 항상 Today. 사용자가 설정에서
    // "마지막 화면 복원"을 켠 경우에만 lastScreen 을 복원한다.
    final s = widget.store.settings;
    _current = s.restoreLastScreen ? s.lastScreen : AppScreen.today;
  }

  void _select(AppScreen screen) {
    if (screen == _current) return;
    setState(() => _current = screen);
    // 마지막 화면을 설정에 기록(단일 mutation 경로 → autosave).
    widget.store.updateSettings((s) => s.copyWith(lastScreen: screen));
  }

  /// 다른 화면(Today/Calendar/Projects)에서 "Gantt 에서 보기" 를 눌렀을 때.
  void openInGantt({PlanFilterState? filter, String? focusNodeId}) {
    setState(() {
      _ganttFilter = filter;
      _ganttFocusNodeId = focusNodeId;
      _current = AppScreen.gantt;
    });
    widget.store.updateSettings((s) => s.copyWith(lastScreen: AppScreen.gantt));
  }

  static const _destinations = <(AppScreen, IconData, IconData)>[
    (AppScreen.today, Icons.today_outlined, Icons.today),
    (AppScreen.gantt, Icons.view_timeline_outlined, Icons.view_timeline),
    (AppScreen.calendar, Icons.calendar_month_outlined, Icons.calendar_month),
    (AppScreen.projects, Icons.folder_outlined, Icons.folder),
    (AppScreen.search, Icons.search_outlined, Icons.search),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      TodayPage(store: widget.store, onOpenInGantt: openInGantt),
      PlanPage(
        store: widget.store,
        initialFilter: _ganttFilter,
        focusNodeId: _ganttFocusNodeId,
      ),
      CalendarPage(store: widget.store, onOpenInGantt: openInGantt),
      ProjectsPage(store: widget.store, onOpenInGantt: openInGantt),
      SearchPage(store: widget.store, onOpenInGantt: openInGantt),
    ];
    final index = AppScreen.values.indexOf(_current);
    // IndexedStack 이라 탭을 바꿔도 각 화면의 스크롤/입력 상태가 유지된다.
    final body = IndexedStack(index: index, children: pages);

    // Ctrl+Z/Ctrl+Y(및 Ctrl+Shift+Z) 는 어느 탭에 있든 동작해야 한다 — Today 의
    // 완료 체크, Gantt 의 드래그/리사이즈, 트리 재정렬이 전부 같은 PlanStore
    // undo 스택을 공유하기 때문이다. 화면별로 따로 바인딩하지 않는다.
    return CallbackShortcuts(
      bindings: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyZ):
            widget.store.undo,
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyY):
            widget.store.redo,
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.keyZ): widget.store.redo,
      },
      child: Focus(
        autofocus: true,
        child: _buildScreen(index, body),
      ),
    );
  }

  Widget _buildScreen(int index, Widget body) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kTwoPaneBreakpoint;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (i) => _select(AppScreen.values[i]),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final (screen, icon, selected) in _destinations)
                      NavigationRailDestination(
                        icon: Icon(icon),
                        selectedIcon: Icon(selected),
                        label: Text(screen.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => _select(AppScreen.values[i]),
            destinations: [
              for (final (screen, icon, selected) in _destinations)
                NavigationDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selected),
                  label: screen.label,
                ),
            ],
          ),
        );
      },
    );
  }
}
