/// PlanBook 의 단일 트리 노드 모델.
///
/// 설계 핵심: 계층의 모든 단계(목표/서브목표/작업/하위작업 ...)가 같은 [PlanNode] 타입으로
/// 표현되며, [parentId] 로 계층을 만든다. 별도 Goal/SubGoal/Task 클래스를 두지 않는다
/// (별도 타입은 깊이 제한을 만든다).
///
/// **원본 값 보존 원칙**: [startDate], [endDate], [progress], [isDone] 등은 사용자가
/// 직접 입력한 원본 값이다. [autoRollup]==true 인 노드의 "유효값"은 자식들로부터
/// 별도 계산(plan_rollup)되며, 그 결과가 이 노드의 원본 값을 덮어쓰지 않는다.
/// UI 는 rollup 결과를 "유효값"으로만 읽고 표시한다.
library;

import 'package:flutter/foundation.dart';

import '../core/date/plan_date.dart';
import 'bar_color.dart';
import 'plan_enums.dart';

/// 계층 트리의 단일 노드. (immutable, [copyWith] 로 수정)
@immutable
class PlanNode {
  /// 영구 unique ID (uuid v4). 절대 재생성/재할당 금지.
  final String id;

  /// 부모 ID. null 이면 최상위(프로젝트/목표 루트).
  final String? parentId;

  /// 제목.
  final String title;

  /// 시작일(시간 없음). null = 미정.
  final PlanDate? startDate;

  /// 종료일(시간 없음, inclusive = 당일 포함).
  final PlanDate? endDate;

  /// 진행률. 0.0 ~ 1.0 범위.
  final double progress;

  /// 진행 상태. 완료 여부는 이 값에서 파생된다([isDone]).
  /// [TaskStatus.onHold](보류)는 완료가 아니다.
  final TaskStatus status;

  /// 우선순위.
  final Priority priority;

  /// 소속 프로젝트 ID. null 이면 "미분류".
  ///
  /// **[parentId] 와 혼동하지 말 것**: [parentId] 는 Task 계층(목표>서브목표>작업),
  /// [projectId] 는 최상위 분류(업무/연구/...) 소속이다.
  final String? projectId;

  /// 태그 ID 목록([Tag.id] 참조).
  final List<String> tagIds;

  /// 마일스톤 여부. true 면 Gantt 에서 막대 대신 마름모로 표시한다.
  final bool isMilestone;

  /// 메모.
  final String? memo;

  /// 예상 작업량(rollup 가중치에도 사용). optional.
  final num? estimate;

  /// 실제 작업량. optional.
  final num? actual;

  /// [nodeKind]==quantity/effort 일 때 [estimate]/[actual] 의 단위 표시용
  /// 라벨(예: "page", "시간"). 계산에는 쓰이지 않고 Today/편집 화면 표시용.
  final String? unit;

  /// 같은 부모 아래 형제들 사이의 순서.
  /// double 로 두어 두 값 사이에 끼워넣기(reorder) 시 재색인을 최소화한다.
  final double sortOrder;

  /// 트리 접기/펼치기 상태(UI 전용 영속 상태).
  final bool isCollapsed;

  /// 노드 종류(현재 project 만 사용, quantity/recurring 은 예약).
  final NodeKind nodeKind;

  /// Gantt 막대 색상(고정 팔레트). [BarColor.none] 이면 "색 지정 안 함".
  final BarColor barColor;

  /// true 면 startDate/endDate/progress/isDone 을 자식으로부터 계산(rollup).
  final bool autoRollup;

  /// [nodeKind]==recurring 일 때의 반복 주기. `RecurrenceFreq.name`
  /// ('daily'/'weekly'/'monthly'). 이 파일은 순환 참조를 피하기 위해
  /// `RecurrenceRule` 타입 자체를 직접 쓰지 않고 평탄화된 필드만 갖는다 —
  /// 구조화된 접근은 `domain/recurrence.dart` 의 확장(extension)을 참고.
  final String? recurrenceFreq;

  /// [recurrenceFreq]=='weekly' 일 때만 사용. `DateTime.monday`(1)~`sunday`(7).
  final List<int> recurrenceWeekdays;

  /// [recurrenceFreq]=='monthly' 일 때만 사용. 1~31.
  final int? recurrenceDayOfMonth;

  /// 반복 occurrence 별 완료 기록(ISO 날짜 문자열 집합). 이 노드 자체의
  /// [status] 는 반복 occurrence 완료 여부와 무관하다 — 원본을 done 처리하면
  /// 미래 occurrence 가 전부 사라지는 것과 같아지므로 절대 그렇게 하지 않는다.
  final List<String> recurrenceCompletedDates;

  const PlanNode({
    required this.id,
    this.parentId,
    required this.title,
    this.startDate,
    this.endDate,
    this.progress = 0.0,
    this.status = TaskStatus.notStarted,
    this.priority = Priority.none,
    this.projectId,
    this.tagIds = const <String>[],
    this.isMilestone = false,
    this.memo,
    this.estimate,
    this.actual,
    this.unit,
    this.sortOrder = 0.0,
    this.isCollapsed = false,
    this.nodeKind = NodeKind.project,
    this.barColor = BarColor.none,
    this.autoRollup = true,
    this.recurrenceFreq,
    this.recurrenceWeekdays = const <int>[],
    this.recurrenceDayOfMonth,
    this.recurrenceCompletedDates = const <String>[],
  });

  /// 완료 여부는 **저장 필드가 아니라 [status] 에서 파생**된다.
  /// [TaskStatus.onHold](보류)는 완료가 아니다.
  bool get isDone => status == TaskStatus.done;

  /// 진행률을 0..1 로 정규화해 반환. (rollup/저장은 항상 정규화값 사용)
  double get clampedProgress => progress.clamp(0.0, 1.0);

  /// 부분 수정. `isDone` 파라미터는 없다 — 완료는 [status] 로만 바꾼다.
  PlanNode copyWith({
    String? id,
    Object? parentId = _sentinel,
    String? title,
    PlanDate? startDate,
    PlanDate? endDate,
    double? progress,
    TaskStatus? status,
    Priority? priority,
    Object? projectId = _sentinel,
    Object? memo = _sentinel,
    Object? estimate = _sentinel,
    Object? actual = _sentinel,
    Object? unit = _sentinel,
    double? sortOrder,
    bool? isCollapsed,
    NodeKind? nodeKind,
    BarColor? barColor,
    bool? autoRollup,
    List<String>? tagIds,
    bool? isMilestone,
    Object? recurrenceFreq = _sentinel,
    List<int>? recurrenceWeekdays,
    Object? recurrenceDayOfMonth = _sentinel,
    List<String>? recurrenceCompletedDates,
  }) {
    return PlanNode(
      id: id ?? this.id,
      parentId: identical(parentId, _sentinel)
          ? this.parentId
          : parentId as String?,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      projectId: identical(projectId, _sentinel)
          ? this.projectId
          : projectId as String?,
      tagIds: tagIds ?? List<String>.unmodifiable(this.tagIds),
      isMilestone: isMilestone ?? this.isMilestone,
      memo: identical(memo, _sentinel) ? this.memo : memo as String?,
      estimate: identical(estimate, _sentinel) ? this.estimate : estimate as num?,
      actual: identical(actual, _sentinel) ? this.actual : actual as num?,
      unit: identical(unit, _sentinel) ? this.unit : unit as String?,
      sortOrder: sortOrder ?? this.sortOrder,
      isCollapsed: isCollapsed ?? this.isCollapsed,
      nodeKind: nodeKind ?? this.nodeKind,
      barColor: barColor ?? this.barColor,
      autoRollup: autoRollup ?? this.autoRollup,
      recurrenceFreq: identical(recurrenceFreq, _sentinel)
          ? this.recurrenceFreq
          : recurrenceFreq as String?,
      recurrenceWeekdays: recurrenceWeekdays ?? this.recurrenceWeekdays,
      recurrenceDayOfMonth: identical(recurrenceDayOfMonth, _sentinel)
          ? this.recurrenceDayOfMonth
          : recurrenceDayOfMonth as int?,
      recurrenceCompletedDates:
          recurrenceCompletedDates ?? this.recurrenceCompletedDates,
    );
  }

  /// 일관성: nullable 시작을 명시적으로 지우고 싶을 때는 아래 헬퍼 사용.
  PlanNode clearDates() => copyWithClearDates();
  PlanNode copyWithClearDates() => PlanNode(
        id: id,
        parentId: parentId,
        title: title,
        startDate: null,
        endDate: null,
        progress: progress,
        status: status,
        priority: priority,
        projectId: projectId,
        tagIds: tagIds,
        isMilestone: isMilestone,
        memo: memo,
        estimate: estimate,
        actual: actual,
        unit: unit,
        sortOrder: sortOrder,
        isCollapsed: isCollapsed,
        nodeKind: nodeKind,
        barColor: barColor,
        autoRollup: autoRollup,
        recurrenceFreq: recurrenceFreq,
        recurrenceWeekdays: recurrenceWeekdays,
        recurrenceDayOfMonth: recurrenceDayOfMonth,
        recurrenceCompletedDates: recurrenceCompletedDates,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        if (parentId != null) 'parentId': parentId,
        'title': title,
        if (startDate != null) 'startDate': startDate!.toIso(),
        if (endDate != null) 'endDate': endDate!.toIso(),
        'progress': progress,
        'status': status.name,
        'priority': priority.name,
        if (projectId != null) 'projectId': projectId,
        if (tagIds.isNotEmpty) 'tagIds': tagIds,
        if (isMilestone) 'isMilestone': isMilestone,
        if (memo != null) 'memo': memo,
        if (estimate != null) 'estimate': estimate,
        if (actual != null) 'actual': actual,
        if (unit != null) 'unit': unit,
        'sortOrder': sortOrder,
        'isCollapsed': isCollapsed,
        'nodeKind': nodeKind.name,
        if (barColor != BarColor.none) 'barColor': barColor.name,
        'autoRollup': autoRollup,
        if (recurrenceFreq != null) 'recurrenceFreq': recurrenceFreq,
        if (recurrenceWeekdays.isNotEmpty)
          'recurrenceWeekdays': recurrenceWeekdays,
        if (recurrenceDayOfMonth != null)
          'recurrenceDayOfMonth': recurrenceDayOfMonth,
        if (recurrenceCompletedDates.isNotEmpty)
          'recurrenceCompletedDates': recurrenceCompletedDates,
      };

  /// 알려진 필드만 파싱하고, 알 수 없는 필드는 무시한다. (forward-compat)
  /// 형식 오류가 있어도 가능한 범위에서 복구한다.
  factory PlanNode.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('PlanNode requires non-empty "id"');
    }
    PlanDate? parseDate(Object? v) {
      if (v == null) return null;
      try {
        return PlanDate.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    return PlanNode(
      id: id,
      parentId: json['parentId']?.toString(),
      title: json['title']?.toString() ?? '',
      startDate: parseDate(json['startDate']),
      endDate: parseDate(json['endDate']),
      progress: _parseDouble(json['progress']) ?? 0.0,
      status: parseStatus(json),
      priority: Priority.fromName(json['priority']?.toString()),
      projectId: json['projectId']?.toString(),
      tagIds: _parseStringList(json['tagIds']),
      isMilestone: json['isMilestone'] == true,
      memo: json['memo']?.toString(),
      estimate: _parseNum(json['estimate']),
      actual: _parseNum(json['actual']),
      unit: json['unit']?.toString(),
      sortOrder: _parseDouble(json['sortOrder']) ?? 0.0,
      isCollapsed: json['isCollapsed'] == true,
      nodeKind: NodeKind.fromName(json['nodeKind']?.toString()),
      barColor: BarColor.fromName(json['barColor']?.toString()),
      autoRollup: json['autoRollup'] != false,
      recurrenceFreq: json['recurrenceFreq']?.toString(),
      recurrenceWeekdays: _parseIntList(json['recurrenceWeekdays']),
      recurrenceDayOfMonth: _parseInt(json['recurrenceDayOfMonth']),
      recurrenceCompletedDates: _parseStringList(json['recurrenceCompletedDates']),
    );
  }

  /// [status] 를 읽는다. 구버전 저장 파일에는 `status` 가 없고 `isDone` 만 있으므로
  /// 그 경우 다음 규칙으로 변환한다(마이그레이션 정책):
  ///   isDone == true            -> done
  ///   isDone == false && p > 0  -> inProgress
  ///   그 외                      -> notStarted
  @visibleForTesting
  static TaskStatus parseStatus(Map<String, Object?> json) {
    final raw = json['status']?.toString();
    if (raw != null) return TaskStatus.fromName(raw);
    if (json['isDone'] == true) return TaskStatus.done;
    final p = _parseDouble(json['progress']) ?? 0.0;
    return p > 0 ? TaskStatus.inProgress : TaskStatus.notStarted;
  }

  @override
  String toString() =>
      'PlanNode($title ${startDate != null ? startDate!.toIso() : '?'}~'
      '${endDate != null ? endDate!.toIso() : '?'} ${(progress * 100).round()}%)';

  @override
  bool operator ==(Object other) =>
      other is PlanNode &&
      other.id == id &&
      other.parentId == parentId &&
      other.title == title &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.progress == progress &&
      other.status == status &&
      other.priority == priority &&
      other.projectId == projectId &&
      _listEq(other.tagIds, tagIds) &&
      other.isMilestone == isMilestone &&
      other.memo == memo &&
      other.estimate == estimate &&
      other.actual == actual &&
      other.unit == unit &&
      other.sortOrder == sortOrder &&
      other.isCollapsed == isCollapsed &&
      other.nodeKind == nodeKind &&
      other.barColor == barColor &&
      other.autoRollup == autoRollup &&
      other.recurrenceFreq == recurrenceFreq &&
      _intListEq(other.recurrenceWeekdays, recurrenceWeekdays) &&
      other.recurrenceDayOfMonth == recurrenceDayOfMonth &&
      _listEq(other.recurrenceCompletedDates, recurrenceCompletedDates);

  @override
  int get hashCode => Object.hash(
        id,
        parentId,
        title,
        startDate,
        endDate,
        progress,
        status,
        priority,
        projectId,
        Object.hashAll(tagIds),
        isMilestone,
        memo,
        estimate,
        actual,
        unit,
        sortOrder,
        isCollapsed,
        nodeKind,
        autoRollup,
        Object.hash(
          barColor,
          recurrenceFreq,
          Object.hashAll(recurrenceWeekdays),
          recurrenceDayOfMonth,
          Object.hashAll(recurrenceCompletedDates),
        ),
      );
}

const Object _sentinel = Object();

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _intListEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<int> _parseIntList(Object? v) {
  if (v is List) {
    return v
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
        .whereType<int>()
        .toList(growable: false);
  }
  return const <int>[];
}

int? _parseInt(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

List<String> _parseStringList(Object? v) {
  if (v is List) {
    return v.map((e) => e.toString()).toList(growable: false);
  }
  return const <String>[];
}

double? _parseDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

num? _parseNum(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}
