/// PlanBook 도메인 열거형 모음.
library;

/// 작업 우선순위.
/// UI 정렬/필터링에 사용되며, JSON 에는 이름 문자열로 직렬화된다.
enum Priority {
  none,
  low,
  medium,
  high;

  static Priority fromName(String? name) {
    if (name == null) return Priority.none;
    for (final v in Priority.values) {
      if (v.name == name) return v;
    }
    return Priority.none;
  }

  /// UI 표시용 한글 라벨.
  String get label => switch (this) {
        Priority.none => '없음',
        Priority.low => '낮음',
        Priority.medium => '보통',
        Priority.high => '높음',
      };
}

/// 작업 진행 상태.
///
/// **[done] 만이 "완료"다.** [onHold](보류)는 완료가 아니며, rollup 에서도
/// 완료로 취급하지 않는다. (부모의 "모든 자식 완료" 판정은 [done] 기준)
///
/// JSON 에는 이름 문자열로 직렬화된다.
enum TaskStatus {
  notStarted,
  inProgress,
  done,
  onHold;

  static TaskStatus fromName(String? name) {
    if (name == null) return TaskStatus.notStarted;
    for (final v in TaskStatus.values) {
      if (v.name == name) return v;
    }
    return TaskStatus.notStarted;
  }

  String get label => switch (this) {
        TaskStatus.notStarted => '미시작',
        TaskStatus.inProgress => '진행중',
        TaskStatus.done => '완료',
        TaskStatus.onHold => '보류',
      };
}

/// 노드 종류 — 작업량을 어떻게 다룰지 결정한다.
///
/// - [project]: 일반적인 기간형 계획 노드(start~end, progress). 기본값.
/// - [quantity]: 수량형(예: "책 300page"). [PlanNode.estimate]=목표량,
///   [PlanNode.actual]=현재까지 완료량. 남은 양/남은 기간으로 일일 권장량을
///   계산한다(정수 단위라고 가정해 올림(ceil) — `workload_query.dart`).
/// - [effort]: 시간형(예: "총 20시간"). quantity 와 계산 방식은 같지만,
///   시간은 소수 단위가 자연스러워 올림하지 않는다(예: "하루 2.3시간").
/// - [recurring]: 반복형(예: "월/수/금 운동"). 향후 확장을 위해 예약된 값 —
///   현재는 필드만 존재하고 occurrence 계산은 아직 구현하지 않는다.
enum NodeKind {
  project,
  quantity,
  effort,
  recurring;

  static NodeKind fromName(String? name) {
    if (name == null) return NodeKind.project;
    for (final v in NodeKind.values) {
      if (v.name == name) return v;
    }
    return NodeKind.project;
  }

  String get label => switch (this) {
        NodeKind.project => '프로젝트',
        NodeKind.quantity => '수량형',
        NodeKind.effort => '시간형',
        NodeKind.recurring => '반복형',
      };
}
