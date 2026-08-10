/// 화면 간 이동을 위한 공통 콜백 타입.
///
/// Today/Calendar/Projects 는 이 콜백 하나로 [AppShell] 에게 "Gantt 로 가서
/// 이 필터/이 Task 를 보여줘" 라고 요청한다. 각 화면이 직접 Navigator 나
/// 탭 상태를 조작하지 않는다.
library;

import '../../domain/plan_filter.dart';

typedef OpenInGantt = void Function({
  PlanFilterState? filter,
  String? focusNodeId,
});
