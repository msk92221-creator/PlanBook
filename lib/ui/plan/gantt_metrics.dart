/// Gantt 타임라인의 **날짜 ↔ 픽셀 매핑** 을 한 곳에 모은 순수 로직.
///
/// 설계 원칙 (DESIGN.md / 2단계 요구사항):
/// - 위젯이나 [BuildContext] 에 의존하지 않는 **순수 함수 / 불변 값 객체**.
///   → 단위 테스트가 가능하고, 3단계(드래그/리사이즈)에서 그대로 재사용 가능.
/// - 날짜 계산은 반드시 `core/date/plan_date.dart` 의 JDN 기반 함수만 사용.
///   위젯 안에서 DateTime 산술 / Duration 계산을 하지 않는다.
/// - **inclusive 규칙**: 8/12~8/12 은 1일치 폭([GanttMetrics.widthForRange] → dayWidth 1개 분량).
///
/// 좌표계: 타임라인의 원점(x=0) 은 [GanttMetrics.firstDay] 의 왼쪽 가장자리.
/// 하루는 폭 [GanttMetrics.dayWidth] 인 칼럼으로 다룬다. 따라서
///   `xForDate(d) = daysBetween(firstDay, d) * dayWidth`
/// 이고 어떤 날짜 d 가 차지하는 가시 칼럼은 `[xForDate(d), xForDate(d)+dayWidth)` 다.
library;

import '../../core/date/plan_date.dart';
import '../../domain/plan_node.dart';

/// 확대/축소의 하한/상한(하루의 픽셀 폭).
///
/// 줌은 **연속적**이다 — 주식 차트처럼 손가락 간격에 비례해 부드럽게 바뀌고,
/// 눈금 단위(일/주/월/분기/년)는 그 축척에서 자동으로 골라진다([GanttZoomLevel.forDayWidth]).
/// 예전처럼 몇 개의 고정 단계를 건너뛰지 않는다.
///
/// - 최소 0.25px/일 → 한 화면(400px)에 약 4년 반.
/// - 최대 64px/일 → 하루 칸이 넉넉히 보이는 최대 확대.
const double kMinDayWidth = 0.25;
const double kMaxDayWidth = 64.0;

/// 하루 폭이 이 값보다 좁으면 **간략 모드**로 그린다.
///
/// 이 축척에서는 막대 하나가 몇 픽셀에 불과하다. 거기에 진행률 분할·테두리·라벨·
/// 마일스톤 마름모까지 전부 그리면 형체를 알아볼 수 없는 픽셀 덩어리가 되고, 정작
/// 알고 싶은 "언제 무엇이 몰려 있는가" 가 안 보인다. 그래서 막대를 단색 한 덩어리로만
/// 그리고 잔가지 장식은 생략한다.
///
/// 드래그도 막는다 — 하루가 2px 도 안 되면 제스처 슬롭(1px 남짓) 만으로 하루 이상
/// 밀려서 날짜를 정확히 바꿀 수 없다. 편집은 확대해서 하는 것이 맞다.
const double kCompactDayWidth = 2.0;

/// 헤더 눈금 단위. **줌 단계가 아니라, 현재 축척에서 자동으로 고르는 눈금 굵기**다.
///
/// 주식 차트가 확대 정도에 따라 분봉→일봉→주봉→월봉으로 바뀌는 것과 같은 개념이다.
/// [dayWidth] 는 확대/축소 버튼이 한 번에 이동할 **프리셋 폭**으로만 쓰인다.
///
/// - [day]: 날짜별 눈금 + 요일 표시. 주말 배경색 구분.
/// - [week]: 주 시작(월요일)마다 눈금.
/// - [month]: 월 경계(1일)마다 눈금.
/// - [quarter]: 분기(1/4/7/10월)마다 눈금.
/// - [year]: 연 경계마다 눈금.
enum GanttZoomLevel {
  /// 일 눈금. 프리셋 40px/일.
  day(40.0, '일', 20.0),

  /// 주 눈금. 프리셋 18px/일 (1주 ≈ 126px).
  week(18.0, '주', 7.0),

  /// 월 눈금. 프리셋 5px/일 (1달 ≈ 150px).
  month(5.0, '월', 2.0),

  /// 분기 눈금. 프리셋 1.4px/일 (1분기 ≈ 128px).
  quarter(1.4, '분기', 0.8),

  /// 연 눈금. 프리셋 0.6px/일 (1년 ≈ 219px).
  year(0.6, '년', 0.0);

  /// 확대/축소 선택 버튼이 이 단계로 이동할 때 쓰는 하루 픽셀 폭(프리셋).
  final double dayWidth;

  /// UI 표시용 한글 라벨.
  final String label;

  /// 이 눈금 단위가 적용되기 시작하는 최소 하루 폭(이 값 이상이면 이 단위를 쓴다).
  final double minDayWidth;

  const GanttZoomLevel(this.dayWidth, this.label, this.minDayWidth);

  /// 현재 축척([dayWidth])에 어울리는 눈금 단위를 고른다.
  ///
  /// 넓을수록 잘게(일), 좁을수록 굵게(년). 경계값은 각 단계의 [minDayWidth] 다.
  static GanttZoomLevel forDayWidth(double dayWidth) {
    for (final z in GanttZoomLevel.values) {
      if (dayWidth >= z.minDayWidth) return z;
    }
    return GanttZoomLevel.year;
  }

  /// 이 **프리셋** 이 간략 모드인지. (실제 판정은 [GanttMetrics.isCompact] 를 쓴다 —
  /// 연속 줌에서는 현재 폭이 기준이지 프리셋이 기준이 아니다.)
  bool get isCompact => dayWidth < kCompactDayWidth;
}

/// 타임라인의 좌표계를 나타내는 불변 값 객체.
///
/// [firstDay]~[lastDay] 구간(양끝 inclusive)을 폭 [dayWidth] 칼럼들로 타일링한다.
/// 모든 좌표 계산은 이 객체의 메서드로 통일한다.
class GanttMetrics {
  /// 타임라인 첫 날(원점, x=0 의 날짜). inclusive.
  final PlanDate firstDay;

  /// 타임라인 마지막 날. inclusive.
  final PlanDate lastDay;

  /// 하루의 픽셀 폭. **연속값**이다(고정 단계가 아니다).
  final double dayWidth;

  const GanttMetrics({
    required this.firstDay,
    required this.lastDay,
    required this.dayWidth,
  });

  /// 현재 축척에 맞는 헤더 눈금 단위. [dayWidth] 에서 **파생**된다 —
  /// 따로 저장하면 둘이 어긋날 수 있어 단일 진실 공급원으로 둔다.
  GanttZoomLevel get zoom => GanttZoomLevel.forDayWidth(dayWidth);

  /// 간략 모드 여부. 프리셋이 아니라 **현재 폭**이 기준이다.
  bool get isCompact => dayWidth < kCompactDayWidth;

  /// 표시 일수(inclusive).
  int get dayCount => inclusiveDayCount(firstDay, lastDay);

  /// 타임라인 전체 폭(px).
  double get totalWidth => dayCount * dayWidth;

  /// [date] 의 왼쪽 가장자리 x 좌표. [firstDay] 이전 날짜면 음수가 될 수 있다.
  double xForDate(PlanDate date) => daysBetween(firstDay, date) * dayWidth;

  /// [start]~[end] inclusive 구간의 픽셀 폭.
  /// 같은 날(start==end)이면 [dayWidth] 1개 분량(0 이 아님).
  /// 둘 중 null 이면 0.
  double widthForRange(PlanDate? start, PlanDate? end) =>
      inclusiveDayCount(start, end) * dayWidth;

  /// x 좌표를 **가장 가까운 날짜 경계**로 스냅하여 역변환.
  ///
  /// `(x / dayWidth).round()` 기반이므로, 한 날짜 칸의 **뒤쪽 절반**이 다음 날로
  /// 스냅된다. 드롭 위치를 하루 단위로 깔끔하게 맞출 때(스냅 용도) 사용한다.
  ///
  /// **주의**: 클릭/히트 테스트(어느 날짜 칸 안에 있는지)에는 [dateForX] 를 쓰면
  /// 안 된다 — 칸 뒤쪽 절반이 다음 날로 판정되어 "하루 밀림" 이 발생한다.
  /// 그 목적에는 [dayColumnForX] 를 사용한다.
  ///
  /// [dayWidth] 가 0 이하이면 [firstDay] 반환(안전장치).
  PlanDate dateForX(double x) {
    if (dayWidth <= 0) return firstDay;
    final dayDelta = (x / dayWidth).round();
    return firstDay.addDays(dayDelta);
  }

  /// x 좌표가 속한 **날짜 칸(column)** 의 날짜. 히트 테스트 / 클릭 / 드롭 판정용.
  ///
  /// `(x / dayWidth).floor()` 기반이므로, 날짜 d 가 차지하는 칸
  /// `[xForDate(d), xForDate(d) + dayWidth)` 안의 모든 x 가 같은 d 로 판정된다.
  /// 음수 x(범위 앞쪽) 도 floor 로 의미대로 동작한다.
  ///
  /// **[dateForX] 와의 차이**: [dateForX] 는 칸의 뒤쪽 절반을 다음 날로 스냅하지만,
  /// [dayColumnForX] 는 칸 전체를 같은 날로 본다. 따라서 클릭/드롭의 "정확한 날짜"
  /// 판정에는 반드시 이쪽을 써야 "하루 밀림" 이 발생하지 않는다.
  ///
  /// [dayWidth] 가 0 이하이면 [firstDay] 반환(안전장치).
  PlanDate dayColumnForX(double x) {
    if (dayWidth <= 0) return firstDay;
    final dayDelta = (x / dayWidth).floor();
    return firstDay.addDays(dayDelta);
  }

  /// [date] 가 타임라인 범위 안(inclusive) 인지.
  bool containsDate(PlanDate date) =>
      daysBetween(firstDay, date) >= 0 && daysBetween(date, lastDay) >= 0;

  /// 오늘 세로선의 x 좌표. = [xForDate] 의 특수형.
  double xForToday(PlanDate today) => xForDate(today);
}

/// 줌 레벨에 따른 [GanttMetrics] 의 표시 범위 계산용 기본 padding(일).
const int kGanttPadDaysBefore = 14;
const int kGanttPadDaysAfter = 30;

/// 보이는(접힘 제외) 노드들과 오늘 기준으로 표시 범위를 정한다.
///
/// - [visibleNodes] 의 유효(rollup 아님, 원본 start/end 기준) 기간의
///   min(start)~max(end) 에 앞뒤 padding 을 더한다.
/// - 날짜가 하나도 없거나 [visibleNodes] 가 비었으면 [today] 기준
///   앞 [padDaysBefore]/뒤 [padDaysAfter] 일을 기본 범위로 쓴다.
///
/// rollup 유효값이 아닌 **노드 원본** 기간으로 범위를 잡는 이유: 뷰가 단순하고,
/// 부모가 자식 기간을 포함하므로 leaf 까지 합치면 결국 전체 기간을 덮게 된다.
GanttMetrics computeGanttMetrics({
  required Iterable<PlanNode> visibleNodes,
  /// 하루의 픽셀 폭(연속값). 호출부가 줌 상태로 들고 있는 값 그대로.
  required double dayWidth,
  required PlanDate today,
  int padDaysBefore = kGanttPadDaysBefore,
  int padDaysAfter = kGanttPadDaysAfter,
}) {
  PlanDate? minStart;
  PlanDate? maxEnd;
  // "열린 기간"(startDate 는 있고 endDate 는 미정) 노드가 하나라도 있으면
  // Gantt 는 그 노드를 start~오늘 까지의 막대로 그린다. 이 막대가 타임라인
  // 오른쪽 밖으로 잘려 나가지 않으려면 maxEnd 후보에 "오늘" 이 포함되어야 한다
  // (예: 2020년에 시작한 종료 미정 항목이 maxEnd 를 2018년으로 잡아버리면
  //  막대의 오른쪽(오늘) 부분이 화면 밖으로 삐져나간다).
  var hasOpenEnded = false;
  for (final n in visibleNodes) {
    final s = n.startDate;
    final e = n.endDate;
    if (s != null) {
      // s 가 현재 minStart 보다 이전이면 갱신(더 빠른 시작).
      if (minStart == null || daysBetween(s, minStart) > 0) minStart = s;
    }
    if (e != null) {
      // e 가 현재 maxEnd 보다 이후면 갱신(더 늦은 끝).
      if (maxEnd == null || daysBetween(maxEnd, e) > 0) maxEnd = e;
    }
    if (s != null && e == null) {
      hasOpenEnded = true;
    }
  }
  // 열린 기간 노드가 있으면 오늘도 maxEnd 후보로 편입한다.
  // (today 를 그대로 maxEnd 로 쓰는 게 아니라 기존 maxEnd 와 비교해 더 큰 쪽을 택한다.
  //  따라서 확정 종료일이 오늘보다 훨씬 뒤인 노드가 섞여 있으면 그 값이 우선한다.)
  // daysBetween(a, b) == b - a 이므로 "today 가 maxEnd 보다 뒤"는 > 0 이다.
  if (hasOpenEnded && (maxEnd == null || daysBetween(maxEnd, today) > 0)) {
    maxEnd = today;
  }

  final PlanDate first;
  final PlanDate last;
  if (minStart == null || maxEnd == null) {
    // 날짜 정보가 전혀 없으면 오늘 기준 기본 범위.
    first = today.addDays(-padDaysBefore);
    last = today.addDays(padDaysAfter);
  } else {
    first = minStart.addDays(-padDaysBefore);
    last = maxEnd.addDays(padDaysAfter);
  }

  return GanttMetrics(
    firstDay: first,
    lastDay: last,
    dayWidth: dayWidth,
  );
}

// ---------------------------------------------------------------------------
// 헤더 눈금(tick) / 셀 생성 — 순수 함수.
// ---------------------------------------------------------------------------

/// 헤더의 한 칸(눈금). [label] 과 [x](원점 기준), [width] 를 가진다.
/// [emphasize]==true 면 굵게/강조 표시(월 경계, 주 시작 등).
class GanttHeaderCell {
  final PlanDate date;

  /// 이 셀이 덮는 일수.
  final int dayCount;

  /// 셀 왼쪽 가장자리 x(원점 기준).
  final double x;

  /// 셀 폭.
  final double width;

  final String label;

  /// 강조 여부(월 시작 등).
  final bool emphasize;

  /// 주말 칸 여부(일 단위에서 사용).
  final bool isWeekend;

  const GanttHeaderCell({
    required this.date,
    required this.dayCount,
    required this.x,
    required this.width,
    required this.label,
    required this.emphasize,
    required this.isWeekend,
  });
}

/// 줌 레벨에 따라 헤더 셀 목록을 생성한다. 순수 함수.
///
/// - 일 단위: 매일 1칸. 월 시작은 강조, 주말 표시.
/// - 주 단위: 매주(월요일) 1칸(7일).
/// - 월 단위: 매월 1칸(가변 일수).
List<GanttHeaderCell> buildHeaderCells(GanttMetrics m) {
  switch (m.zoom) {
    case GanttZoomLevel.day:
      return _dayCells(m);
    case GanttZoomLevel.week:
      return _weekCells(m);
    case GanttZoomLevel.month:
      return _monthCells(m);
    case GanttZoomLevel.quarter:
      return _quarterCells(m);
    case GanttZoomLevel.year:
      return _yearCells(m);
  }
}

const List<String> _kWeekdayShort = [
  '월',
  '화',
  '수',
  '목',
  '금',
  '토',
  '일',
];

int _weekdayOf(PlanDate d) {
  // DateTime.monday=1 .. sunday=7
  return d.toDateTime().weekday;
}

List<GanttHeaderCell> _dayCells(GanttMetrics m) {
  final out = <GanttHeaderCell>[];
  final total = m.dayCount;
  for (var i = 0; i < total; i++) {
    final date = m.firstDay.addDays(i);
    final wd = _weekdayOf(date); // 1..7
    final isWeekend = wd == 6 || wd == 7;
    final isMonthStart = date.day == 1;
    final label = isMonthStart
        ? '${date.month}/${date.day}'
        : '${date.day}';
    out.add(GanttHeaderCell(
      date: date,
      dayCount: 1,
      x: i * m.dayWidth,
      width: m.dayWidth,
      label: label,
      emphasize: isMonthStart,
      isWeekend: isWeekend,
    ));
  }
  return out;
}

List<GanttHeaderCell> _weekCells(GanttMetrics m) {
  final out = <GanttHeaderCell>[];
  // 첫 주의 월요일부터 한 주씩.
  var cursor = startOfWeek(m.firstDay);
  while (daysBetween(cursor, m.lastDay) >= 0) {
    final x = m.xForDate(cursor);
    // 이 주가 범위를 벗어나는 만큼 잘라 폭/라벨은 그대로 두되 x 기준으로 렌더.
    final label = '${cursor.month}/${cursor.day}';
    out.add(GanttHeaderCell(
      date: cursor,
      dayCount: 7,
      x: x,
      width: 7 * m.dayWidth,
      label: label,
      emphasize: true,
      isWeekend: false,
    ));
    cursor = cursor.addDays(7);
  }
  return out;
}

List<GanttHeaderCell> _monthCells(GanttMetrics m) {
  final out = <GanttHeaderCell>[];
  // 첫 달의 1일부터 한 달씩.
  var cursor = startOfMonth(m.firstDay);
  while (daysBetween(cursor, m.lastDay) >= 0) {
    final monthEnd = endOfMonth(cursor);
    final days = inclusiveDayCount(cursor, monthEnd);
    final x = m.xForDate(cursor);
    final label = '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}';
    out.add(GanttHeaderCell(
      date: cursor,
      dayCount: days,
      x: x,
      width: days * m.dayWidth,
      label: label,
      emphasize: true,
      isWeekend: false,
    ));
    // 다음 달 1일.
    cursor = cursor.month == 12
        ? PlanDate(cursor.year + 1, 1, 1)
        : PlanDate(cursor.year, cursor.month + 1, 1);
  }
  return out;
}

/// 분기(1/4/7/10월 1일 시작) 단위 셀. 라벨은 "2026 Q3" 형태.
List<GanttHeaderCell> _quarterCells(GanttMetrics m) {
  final out = <GanttHeaderCell>[];
  // 표시 범위 첫 날이 속한 분기의 첫 달(1/4/7/10)부터 시작한다.
  final firstQuarterMonth = ((m.firstDay.month - 1) ~/ 3) * 3 + 1;
  var cursor = PlanDate(m.firstDay.year, firstQuarterMonth, 1);
  while (daysBetween(cursor, m.lastDay) >= 0) {
    // 이 분기의 마지막 달의 말일.
    final lastMonthOfQuarter = cursor.month + 2;
    final quarterEnd = endOfMonth(PlanDate(cursor.year, lastMonthOfQuarter, 1));
    final days = inclusiveDayCount(cursor, quarterEnd);
    out.add(GanttHeaderCell(
      date: cursor,
      dayCount: days,
      x: m.xForDate(cursor),
      width: days * m.dayWidth,
      label: '${cursor.year} Q${(cursor.month - 1) ~/ 3 + 1}',
      emphasize: true,
      isWeekend: false,
    ));
    // 다음 분기 첫 달.
    cursor = cursor.month >= 10
        ? PlanDate(cursor.year + 1, 1, 1)
        : PlanDate(cursor.year, cursor.month + 3, 1);
  }
  return out;
}

/// 연 단위 셀. 라벨은 "2026".
List<GanttHeaderCell> _yearCells(GanttMetrics m) {
  final out = <GanttHeaderCell>[];
  var cursor = PlanDate(m.firstDay.year, 1, 1);
  while (daysBetween(cursor, m.lastDay) >= 0) {
    final yearEnd = PlanDate(cursor.year, 12, 31);
    final days = inclusiveDayCount(cursor, yearEnd);
    out.add(GanttHeaderCell(
      date: cursor,
      dayCount: days,
      x: m.xForDate(cursor),
      width: days * m.dayWidth,
      label: '${cursor.year}',
      emphasize: true,
      isWeekend: false,
    ));
    cursor = PlanDate(cursor.year + 1, 1, 1);
  }
  return out;
}

/// 일 단위에서 주말(토/일)인 날의 0-based 오프셋([GanttMetrics.firstDay] 기준) 목록.
/// 배경 칠하기용. 순수 함수.
List<int> weekendDayOffsets(GanttMetrics m) {
  if (m.zoom != GanttZoomLevel.day) return const [];
  final out = <int>[];
  final total = m.dayCount;
  for (var i = 0; i < total; i++) {
    final wd = _weekdayOf(m.firstDay.addDays(i));
    if (wd == 6 || wd == 7) out.add(i);
  }
  return out;
}

/// 요일 한글 약자(월..일). UI 헤더에서 사용.
String weekdayShortLabel(PlanDate date) {
  final wd = _weekdayOf(date); // 1..7
  return _kWeekdayShort[wd - 1];
}
