/// Date-only value type used everywhere in PlanBook.
///
/// PlanBook은 "시간 개념이 없는 달력 날짜"만 다룬다. 따라서 [DateTime]의
/// 시/분/초/타임존 성분이 날짜 계산에 끼어드는 버그(DST, timezone, boundary)를
/// 원천 차단하기 위해 별도의 [PlanDate] 값을 사용한다.
///
/// 모든 날짜 계산은 이 파일 안에 모여 있어야 한다. (날짜 처리 정책의 단일 출처)
/// 저장/직렬화 포맷은 항상 ISO `YYYY-MM-DD` 이다. UTC 변환은 하지 않는다.
library;

import 'package:flutter/foundation.dart';

/// 시간 성분이 없는 달력 날짜.
@immutable
class PlanDate implements Comparable<PlanDate> {
  /// 4자리 연도.
  final int year;

  /// 1~12 월.
  final int month;

  /// 1~(월별 일수) 일.
  final int day;

  PlanDate(this.year, this.month, this.day) {
    RangeError.checkValueInInterval(month, 1, 12, 'month');
    RangeError.checkValueInInterval(day, 1, _daysInMonth(year, month), 'day');
  }

  /// [DateTime]에서 날짜 성분만 취해 [PlanDate]를 만든다.
  /// 타임존/시간 성분은 버린다.
  factory PlanDate.fromDateTime(DateTime dt) =>
      PlanDate(dt.year, dt.month, dt.day);

  /// ISO `YYYY-MM-DD` 문자열을 파싱한다. 형식이 맞지 않으면 [FormatException].
  factory PlanDate.parse(String input) {
    final s = input.trim();
    final parts = s.split('-');
    if (parts.length != 3) {
      throw FormatException('Invalid date format (expected YYYY-MM-DD): "$input"');
    }
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    return PlanDate(y, m, d);
  }

  /// `YYYY-MM-DD` 형식의 문자열로 변환. 항상 0패딩.
  String toIso() {
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '${year.toString().padLeft(4, '0')}-$m-$d';
  }

  @override
  String toString() => toIso();

  /// [DateTime]으로 변환한다. 시간 성분은 0, [DateTime.isUtc]는 false 로 정규화.
  DateTime toDateTime() => DateTime(year, month, day);

  /// Julian Day Number(JDN). 모든 일수 차이 계산은 JDN 기반 정수 연산으로
  /// DST/시간 성분의 영향을 받지 않는다.
  int get julianDayNumber => _toJulianDayNumber(year, month, day);

  /// `+delta` 일만큼 이동한 날짜. 음수도 허용.
  PlanDate addDays(int delta) {
    final jd = julianDayNumber + delta;
    final ymd = _fromJulianDayNumber(jd);
    return PlanDate(ymd[0], ymd[1], ymd[2]);
  }

  /// `this` 와 `other` 사이의 일수 차이. 양수면 `other`가 이후.
  /// `other.julianDayNumber - this.julianDayNumber`.
  int daysUntil(PlanDate other) => other.julianDayNumber - julianDayNumber;

  /// 포함 여부 범위 비교 (양끝 inclusive). start/end 가 null 이면 한쪽을 무한으로 본다.
  bool isWithin(PlanDate? start, PlanDate? end) {
    if (start != null && daysUntil(start) > 0) return false; // this < start
    if (end != null && end.daysUntil(this) > 0) return false; // this > end
    return true;
  }

  @override
  int compareTo(PlanDate other) {
    final r = julianDayNumber - other.julianDayNumber;
    if (r < 0) return -1;
    if (r > 0) return 1;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is PlanDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  // ---- 내부 달력 헬퍼 ----

  static int _daysInMonth(int year, int month) {
    if (month == 2) {
      return _isLeapYear(year) ? 29 : 28;
    }
    if (month == 4 || month == 6 || month == 9 || month == 11) {
      return 30;
    }
    return 31;
  }

  static bool _isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);

  /// Gregorian 달력의 Julian Day Number. (정수, 정확)
  /// https://en.wikipedia.org/wiki/Julian_day 변환 공식 사용.
  static int _toJulianDayNumber(int year, int month, int day) {
    final a = (14 - month) ~/ 12;
    final y = year + 4800 - a;
    final m = month + 12 * a - 3;
    return day +
        (153 * m + 2) ~/ 5 +
        365 * y +
        y ~/ 4 -
        y ~/ 100 +
        y ~/ 400 -
        32045;
  }

  /// JDN → (year, month, day).
  static List<int> _fromJulianDayNumber(int jd) {
    final a = jd + 32044;
    final b = (4 * a + 3) ~/ 146097;
    final c = a - (146097 * b) ~/ 4;
    final d = (4 * c + 3) ~/ 1461;
    final e = c - (1461 * d) ~/ 4;
    final m = (5 * e + 2) ~/ 153;
    final day = e - (153 * m + 2) ~/ 5 + 1;
    final month = m + 3 - 12 * (m ~/ 10);
    final year = 100 * b + d - 4800 + m ~/ 10;
    return [year, month, day];
  }
}

/// [DateTime] 시간 성분 제거/정규화 유틸.
/// [DateTime]을 직접 다뤄야 할 때만 사용하고, 가급적 [PlanDate]를 쓸 것.
DateTime normalizeDateTime(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// 두 날짜 사이의 일수 차이(정수). DST/시간 성분 영향 없음.
/// `b`가 `a` 이후면 양수.
int daysBetween(PlanDate a, PlanDate b) => b.julianDayNumber - a.julianDayNumber;

/// inclusive 구간 `[start, end]` 가 덮는 일 수.
/// start/end 가 null 이면 0. end < start 면 0(빈 구간).
int inclusiveDayCount(PlanDate? start, PlanDate? end) {
  if (start == null || end == null) return 0;
  final diff = end.julianDayNumber - start.julianDayNumber + 1;
  return diff < 0 ? 0 : diff;
}

/// 특정 날짜가 inclusive 구간 `[start, end]` 안에 있는지.
/// start/end 중 null 인 쪽은 무한으로 간주. 둘 다 null 이면 항상 true.
///
/// (노드 기반 판정은 도메인 layer 의 `coversDate(PlanNode, PlanDate)` 를 사용.
///  본 파일은 날짜 원시 연산만 담당하며, 이름 충돌을 피하기 위해
///  편의 함수명은 [PlanDate.isWithin] 과 동일 의미로 여기서는 별도로 노출하지 않는다.)
bool dateWithin(PlanDate date, PlanDate? start, PlanDate? end) =>
    date.isWithin(start, end);

/// 두 inclusive 구간 `[s1,e1]` / `[s2,e2]` 가 겹치는지.
/// null 한계는 무한으로 간주. 둘 다 완전히 null 이면 겹침(true).
bool overlapsRange(
  PlanDate? s1,
  PlanDate? e1,
  PlanDate? s2,
  PlanDate? e2,
) {
  // 한쪽이 완전히 무한(null,null) 이면 항상 겹침.
  if (s1 == null && e1 == null) return true;
  if (s2 == null && e2 == null) return true;
  // end1 < start2 또는 end2 < start1 인 경우에만 안 겹침.
  if (e1 != null && s2 != null && daysBetween(e1, s2) > 0) return false;
  if (e2 != null && s1 != null && daysBetween(e2, s1) > 0) return false;
  return true;
}

/// Gantt 드래그용: 픽셀 이동량을 일수로 변환.
/// 반올림 규칙은 (dx/dayWidth).round() 로 단일 정의.
/// 0.4일 → 0, 0.6일 → 1, -0.6일 → -1.
int dayDeltaFromPixels(double dx, double dayWidth) {
  if (dayWidth <= 0) return 0;
  return (dx / dayWidth).round();
}

/// 기간 길이를 보존하면서 [start],[end] 를 [dayDelta] 일만큼 이동.
/// 둘 중 하나라도 null 이면 그대로 반환(이동 불가).
({PlanDate? start, PlanDate? end}) shiftRange(
  PlanDate? start,
  PlanDate? end,
  int dayDelta,
) {
  if (start == null && end == null) return (start: null, end: null);
  final ns = start?.addDays(dayDelta);
  final ne = end?.addDays(dayDelta);
  return (start: ns, end: ne);
}

/// Gantt 바 **좌측 핸들** 리사이즈: 시작일만 [dayDelta] 일만큼 이동.
/// 최소 1일(inclusive) 보장을 위해 [origEnd] 를 넘어가면 [origEnd] 로 clamp.
/// (8/14~8/16 에서 시작 핸들을 +4일 → 8/18~8/16 은 무효 → 8/16~8/16, 1일)
PlanDate resizeStart(PlanDate origStart, PlanDate origEnd, int dayDelta) {
  final ns = origStart.addDays(dayDelta);
  return daysBetween(ns, origEnd) >= 0 ? ns : origEnd;
}

/// Gantt 바 **우측 핸들** 리사이즈: 종료일만 [dayDelta] 일만큼 이동.
/// 최소 1일(inclusive) 보장을 위해 [origStart] 밑으로 내려가면 [origStart] 로 clamp.
/// (8/12~8/16 에서 종료 핸들을 -6일 → 8/12~8/10 은 무효 → 8/12~8/12, 1일)
PlanDate resizeEnd(PlanDate origStart, PlanDate origEnd, int dayDelta) {
  final ne = origEnd.addDays(dayDelta);
  return daysBetween(origStart, ne) >= 0 ? ne : origStart;
}

/// 주(Week)의 시작 요일. PlanBook은 월요일 시작을 기본 정책으로 한다.
/// (일요일=DateTime.sunday, 월요일=DateTime.monday ...)
const int kWeekStartWeekday = DateTime.monday;

/// 주어진 날짜가 속한 주(월요일 시작)의 시작 날짜.
PlanDate startOfWeek(PlanDate date) => startOfWeekWith(date, kWeekStartWeekday);

/// 주어진 날짜가 속한 주(월요일 시작 ~ 일요일)의 끝 날짜.
PlanDate endOfWeek(PlanDate date) => startOfWeek(date).addDays(6);

/// [startOfWeek] 의 설정 가능한 버전. [weekStartWeekday] 는 `DateTime.monday`(1)
/// ~ `DateTime.sunday`(7) 값 — [AppSettings.weekStart] 를 그대로 넘기면 된다.
PlanDate startOfWeekWith(PlanDate date, int weekStartWeekday) {
  final dt = date.toDateTime();
  final diff = (dt.weekday - weekStartWeekday) % 7;
  final shift = diff < 0 ? diff + 7 : diff;
  return date.addDays(-shift);
}

/// [endOfWeek] 의 설정 가능한 버전.
PlanDate endOfWeekWith(PlanDate date, int weekStartWeekday) =>
    startOfWeekWith(date, weekStartWeekday).addDays(6);

/// 주어진 날짜가 속한 월의 시작일(1일).
PlanDate startOfMonth(PlanDate date) => PlanDate(date.year, date.month, 1);

/// 주어진 날짜가 속한 월의 마지막 날짜.
PlanDate endOfMonth(PlanDate date) {
  // 다음 달 1일에서 하루 빼기 → 이번 달 마지막 날.
  // 반드시 JDN 기반(addDays)으로 계산한다. DateTime + Duration 산술은 절대시간
  // (24시간) 이동이라서 DST 전환 구간에 걸치면 하루가 밀릴 수 있어 이 파일의
  // "시간 성분 영향 차단" 설계 원칙에 어긋난다.
  final firstOfNext = date.month == 12
      ? PlanDate(date.year + 1, 1, 1)
      : PlanDate(date.year, date.month + 1, 1);
  return firstOfNext.addDays(-1);
}

/// 편의: [DateTime] clock 함수 타입. 테스트에서 고정 시각을 주입하기 위함.
typedef DateProvider = PlanDate Function();
typedef DateTimeProvider = DateTime Function();

/// 기본 clock (실제 현재 시각).
PlanDate todayDate({DateTimeProvider? now}) {
  final dt = (now ?? DateTime.now)();
  return PlanDate(dt.year, dt.month, dt.day);
}
