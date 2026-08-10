import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';

void main() {
  group('PlanDate.parse / toIso', () {
    test('round-trip YYYY-MM-DD', () {
      final d = PlanDate(2024, 8, 16);
      expect(d.toIso(), '2024-08-16');
      expect(PlanDate.parse('2024-08-16'), d);
    });

    test('reject invalid format', () {
      expect(() => PlanDate.parse('2024/08/16'), throwsA(isA<FormatException>()));
      expect(() => PlanDate.parse('bad'), throwsA(isA<FormatException>()));
    });

    test('reject out-of-range day/month', () {
      expect(() => PlanDate(2024, 13, 1), throwsA(isA<RangeError>()));
      expect(() => PlanDate(2024, 2, 30), throwsA(isA<RangeError>()));
    });
  });

  group('normalizeDateTime', () {
    test('strips time components and sets isUtc=false', () {
      final raw = DateTime(2024, 8, 16, 17, 5, 9);
      final n = normalizeDateTime(raw);
      expect(n.year, 2024);
      expect(n.month, 8);
      expect(n.day, 16);
      expect(n.hour, 0);
      expect(n.minute, 0);
      expect(n.second, 0);
      expect(n.isUtc, false);
    });

    test('PlanDate.fromDateTime ignores time', () {
      final d = PlanDate.fromDateTime(DateTime(2024, 8, 16, 23, 59, 59));
      expect(d, PlanDate(2024, 8, 16));
    });
  });

  group('daysBetween (month/year/leap boundaries)', () {
    test('same day = 0', () {
      expect(daysBetween(PlanDate(2024, 8, 16), PlanDate(2024, 8, 16)), 0);
    });

    test('month boundary end→start = 1', () {
      // Feb 28 -> Mar 1
      expect(daysBetween(PlanDate(2023, 2, 28), PlanDate(2023, 3, 1)), 1);
    });

    test('year boundary Dec31 -> Jan1 = 1', () {
      expect(daysBetween(PlanDate(2023, 12, 31), PlanDate(2024, 1, 1)), 1);
    });

    test('leap year Feb exists', () {
      // 2024 is leap: Feb 29 exists.
      expect(daysBetween(PlanDate(2024, 2, 28), PlanDate(2024, 2, 29)), 1);
      expect(daysBetween(PlanDate(2024, 2, 29), PlanDate(2024, 3, 1)), 1);
    });

    test('non-leap year Feb has 28 days', () {
      // 2023 non-leap: Feb 28 -> Mar 1 is 1 day (no Feb 29).
      expect(() => PlanDate(2023, 2, 29), throwsA(isA<RangeError>()));
    });

    test('long span across DST (uses JDN, immune to DST)', () {
      // Jan 1 2024 -> Dec 31 2024 = 365 days (2024 is leap so year has 366 days).
      expect(daysBetween(PlanDate(2024, 1, 1), PlanDate(2024, 12, 31)), 365);
    });

    test('negative when reversed', () {
      expect(daysBetween(PlanDate(2024, 8, 18), PlanDate(2024, 8, 16)), -2);
    });
  });

  group('addDays', () {
    test('cross month boundary', () {
      expect(PlanDate(2024, 1, 31).addDays(1), PlanDate(2024, 2, 1));
      expect(PlanDate(2024, 2, 29).addDays(1), PlanDate(2024, 3, 1));
    });
    test('negative', () {
      expect(PlanDate(2024, 3, 1).addDays(-1), PlanDate(2024, 2, 29));
    });
  });

  group('inclusiveDayCount', () {
    test('inclusive count includes both endpoints', () {
      expect(inclusiveDayCount(PlanDate(2024, 8, 12), PlanDate(2024, 8, 16)), 5);
    });
    test('null returns 0', () {
      expect(inclusiveDayCount(null, PlanDate(2024, 8, 16)), 0);
      expect(inclusiveDayCount(PlanDate(2024, 8, 12), null), 0);
    });
  });

  group('dateWithin (inclusive both ends)', () {
    final start = PlanDate(2024, 8, 12);
    final end = PlanDate(2024, 8, 16);
    test('start day included', () {
      expect(dateWithin(start, start, end), isTrue);
    });
    test('end day included', () {
      expect(dateWithin(end, start, end), isTrue);
    });
    test('day before start excluded', () {
      expect(dateWithin(PlanDate(2024, 8, 11), start, end), isFalse);
    });
    test('day after end excluded', () {
      expect(dateWithin(PlanDate(2024, 8, 17), start, end), isFalse);
    });
    test('null bounds = always within', () {
      expect(dateWithin(PlanDate(2024, 8, 16), null, null), isTrue);
    });
    test('open-ended (only start)', () {
      expect(dateWithin(PlanDate(2099, 1, 1), start, null), isTrue);
      expect(dateWithin(PlanDate(2024, 8, 11), start, null), isFalse);
    });
    test('PlanDate.isWithin method equivalent', () {
      expect(PlanDate(2024, 8, 13).isWithin(start, end), isTrue);
      expect(PlanDate(2024, 8, 17).isWithin(start, end), isFalse);
    });
  });

  group('overlapsRange', () {
    final a1 = PlanDate(2024, 8, 10);
    final a2 = PlanDate(2024, 8, 15);
    test('partial overlap', () {
      expect(overlapsRange(a1, a2, PlanDate(2024, 8, 14), PlanDate(2024, 8, 20)),
          isTrue);
    });
    test('touching endpoints overlap (inclusive)', () {
      expect(overlapsRange(a1, a2, PlanDate(2024, 8, 15), PlanDate(2024, 8, 20)),
          isTrue);
      expect(overlapsRange(a1, a2, PlanDate(2024, 8, 5), PlanDate(2024, 8, 10)),
          isTrue);
    });
    test('disjoint ranges do not overlap', () {
      expect(overlapsRange(a1, a2, PlanDate(2024, 8, 16), PlanDate(2024, 8, 20)),
          isFalse);
    });
    test('unbounded side always overlaps', () {
      expect(overlapsRange(null, null, a1, a2), isTrue);
      expect(overlapsRange(a1, a2, null, null), isTrue);
    });
  });

  group('dayDeltaFromPixels (rounding)', () {
    const dayWidth = 10.0;
    test('0.4 day -> 0', () {
      expect(dayDeltaFromPixels(4.0, dayWidth), 0);
    });
    test('0.6 day -> 1', () {
      expect(dayDeltaFromPixels(6.0, dayWidth), 1);
    });
    test('-0.6 day -> -1', () {
      expect(dayDeltaFromPixels(-6.0, dayWidth), -1);
    });
    test('exact half -> rounds to nearest even? (Dart .round is round half away from zero)',
        () {
      // 5/10 = 0.5 -> round half away from zero -> 1
      expect(dayDeltaFromPixels(5.0, dayWidth), 1);
      expect(dayDeltaFromPixels(-5.0, dayWidth), -1);
    });
    test('non-positive dayWidth -> 0', () {
      expect(dayDeltaFromPixels(10.0, 0), 0);
      expect(dayDeltaFromPixels(10.0, -1), 0);
    });
  });

  group('shiftRange (preserves duration)', () {
    test('8/12~8/16 +2 => 8/14~8/18', () {
      final start = PlanDate(2024, 8, 12);
      final end = PlanDate(2024, 8, 16);
      final shifted = shiftRange(start, end, 2);
      expect(shifted.start, PlanDate(2024, 8, 14));
      expect(shifted.end, PlanDate(2024, 8, 18));
    });
    test('duration preserved', () {
      final start = PlanDate(2024, 8, 12);
      final end = PlanDate(2024, 8, 16);
      final before = inclusiveDayCount(start, end);
      final shifted = shiftRange(start, end, 2);
      expect(inclusiveDayCount(shifted.start, shifted.end), before);
    });
    test('negative shift across month boundary', () {
      final start = PlanDate(2024, 9, 3);
      final end = PlanDate(2024, 9, 5);
      final shifted = shiftRange(start, end, -5);
      expect(shifted.start, PlanDate(2024, 8, 29));
      expect(shifted.end, PlanDate(2024, 8, 31));
    });
    test('both null stays null', () {
      final shifted = shiftRange(null, null, 5);
      expect(shifted.start, isNull);
      expect(shifted.end, isNull);
    });
  });

  group('resizeStart (left handle, min 1 day)', () {
    test('8/12~8/16 +2일 => 8/14~8/16 (시작일만 이동)', () {
      final newStart = resizeStart(PlanDate(2024, 8, 12), PlanDate(2024, 8, 16), 2);
      expect(newStart, PlanDate(2024, 8, 14));
    });
    test('시작일이 종료일을 넘으려 하면 종료일로 clamp (최소 1일)', () {
      // 8/14~8/16 에서 +4일 → 8/18 은 end(8/16) 를 넘음 → 8/16 으로 clamp.
      final newStart = resizeStart(PlanDate(2024, 8, 14), PlanDate(2024, 8, 16), 4);
      expect(newStart, PlanDate(2024, 8, 16));
    });
    test('시작일 == 종료일 인 순간까지는 허용(1일 보장)', () {
      final newStart = resizeStart(PlanDate(2024, 8, 14), PlanDate(2024, 8, 16), 2);
      expect(newStart, PlanDate(2024, 8, 16)); // == end, 1일 보장
    });
    test('음수 dayDelta 도 자유롭게(기간 늘어남)', () {
      final newStart = resizeStart(PlanDate(2024, 8, 14), PlanDate(2024, 8, 16), -5);
      expect(newStart, PlanDate(2024, 8, 9));
    });
  });

  group('resizeEnd (right handle, min 1 day)', () {
    test('8/12~8/16 +2일 => 종료일 8/18', () {
      final newEnd = resizeEnd(PlanDate(2024, 8, 12), PlanDate(2024, 8, 16), 2);
      expect(newEnd, PlanDate(2024, 8, 18));
    });
    test('종료일이 시작일 밑으로 내려가면 시작일로 clamp (최소 1일)', () {
      // 8/12~8/16 에서 -6일 → 8/10 은 start(8/12) 이전 → 8/12 로 clamp.
      final newEnd = resizeEnd(PlanDate(2024, 8, 12), PlanDate(2024, 8, 16), -6);
      expect(newEnd, PlanDate(2024, 8, 12));
    });
    test('종료일 == 시작일 인 순간까지는 허용(1일 보장)', () {
      final newEnd = resizeEnd(PlanDate(2024, 8, 12), PlanDate(2024, 8, 16), -4);
      expect(newEnd, PlanDate(2024, 8, 12)); // == start, 1일 보장
    });
  });

  group('startOfWeek (Monday-based)', () {
    test('Sunday -> previous Monday', () {
      // 2024-01-07 is Sunday.
      expect(startOfWeek(PlanDate(2024, 1, 7)), PlanDate(2024, 1, 1));
    });
    test('Monday -> itself', () {
      expect(startOfWeek(PlanDate(2024, 1, 1)), PlanDate(2024, 1, 1));
    });
    test('endOfWeek = Monday + 6 (Sunday)', () {
      expect(endOfWeek(PlanDate(2024, 1, 3)), PlanDate(2024, 1, 7));
    });
    test('week boundary across year (2023-01-01 is Sunday)', () {
      // 2023-01-01 is Sunday -> start of week is 2022-12-26 (Monday).
      expect(startOfWeek(PlanDate(2023, 1, 1)), PlanDate(2022, 12, 26));
    });
  });

  group('startOfMonth / endOfMonth', () {
    test('mid month', () {
      expect(startOfMonth(PlanDate(2024, 8, 15)), PlanDate(2024, 8, 1));
      expect(endOfMonth(PlanDate(2024, 8, 15)), PlanDate(2024, 8, 31));
    });
    test('leap February', () {
      expect(endOfMonth(PlanDate(2024, 2, 10)), PlanDate(2024, 2, 29));
      expect(endOfMonth(PlanDate(2023, 2, 10)), PlanDate(2023, 2, 28));
    });
    test('December', () {
      expect(endOfMonth(PlanDate(2024, 12, 5)), PlanDate(2024, 12, 31));
    });
  });

  // ---- 버그 #3 회귀 테스트: endOfMonth (JDN 기반) ----
  group('endOfMonth across months/leap (regression for bug #3)', () {
    test('31-day months (Jan, Mar, May, Jul, Aug, Oct, Dec)', () {
      expect(endOfMonth(PlanDate(2026, 1, 10)), PlanDate(2026, 1, 31));
      expect(endOfMonth(PlanDate(2026, 3, 1)), PlanDate(2026, 3, 31));
      expect(endOfMonth(PlanDate(2026, 5, 15)), PlanDate(2026, 5, 31));
      expect(endOfMonth(PlanDate(2026, 7, 31)), PlanDate(2026, 7, 31));
      expect(endOfMonth(PlanDate(2026, 8, 16)), PlanDate(2026, 8, 31));
      expect(endOfMonth(PlanDate(2026, 10, 1)), PlanDate(2026, 10, 31));
    });
    test('30-day months (Apr, Jun, Sep, Nov)', () {
      expect(endOfMonth(PlanDate(2026, 4, 5)), PlanDate(2026, 4, 30));
      expect(endOfMonth(PlanDate(2026, 6, 1)), PlanDate(2026, 6, 30));
      expect(endOfMonth(PlanDate(2026, 9, 15)), PlanDate(2026, 9, 30));
      expect(endOfMonth(PlanDate(2026, 11, 30)), PlanDate(2026, 11, 30));
    });
    test('February common year = 28', () {
      expect(endOfMonth(PlanDate(2026, 2, 1)), PlanDate(2026, 2, 28));
      expect(endOfMonth(PlanDate(1900, 2, 15)), PlanDate(1900, 2, 28),
          reason: '1900 is NOT a leap year (divisible by 100, not 400)');
    });
    test('February leap year = 29 (2024 divisible by 4, 2000 by 400)', () {
      expect(endOfMonth(PlanDate(2024, 2, 1)), PlanDate(2024, 2, 29));
      expect(endOfMonth(PlanDate(2000, 2, 29)), PlanDate(2000, 2, 29),
          reason: '2000 IS a leap year (divisible by 400)');
    });
    test('December does not roll into next year', () {
      // JDN addDays(-1) path must keep the year correct.
      expect(endOfMonth(PlanDate(2026, 12, 1)), PlanDate(2026, 12, 31));
      expect(endOfMonth(PlanDate(2026, 12, 31)), PlanDate(2026, 12, 31));
      expect(endOfMonth(PlanDate(2026, 12, 15)).year, 2026);
    });
    test('input day is irrelevant (any day in month → same last day)', () {
      final first = endOfMonth(PlanDate(2026, 2, 1));
      final mid = endOfMonth(PlanDate(2026, 2, 14));
      final last = endOfMonth(PlanDate(2026, 2, 28));
      expect(first, last);
      expect(mid, last);
      expect(last, PlanDate(2026, 2, 28));
    });
  });

  group('comparable & equality', () {
    test('compareTo ordering', () {
      final a = PlanDate(2024, 8, 1);
      final b = PlanDate(2024, 8, 2);
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
      expect(a.compareTo(a), 0);
    });
  });
}
