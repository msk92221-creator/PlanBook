import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/ui/plan/gantt_metrics.dart';

GanttMetrics _metrics({
  required PlanDate first,
  required PlanDate last,
  required double dayWidth,
}) {
  return GanttMetrics(
    firstDay: first,
    lastDay: last,
    dayWidth: dayWidth,
  );
}

void main() {
  _zoomOutLevelsTests();
  group('xForDate / dateForX round-trip', () {
    test('여러 줌 레벨에서 왕복 일치', () {
      for (final zoom in GanttZoomLevel.values) {
        final m = _metrics(
          first: PlanDate(2024, 8, 1),
          last: PlanDate(2024, 8, 31),
          dayWidth: zoom.dayWidth,
        );
        for (final d in [
          PlanDate(2024, 8, 1),
          PlanDate(2024, 8, 15),
          PlanDate(2024, 8, 31),
        ]) {
          expect(m.dateForX(m.xForDate(d)), d, reason: 'zoom=$zoom, date=$d');
        }
      }
    });

    test('firstDay 의 x 는 0', () {
      final m = _metrics(
        first: PlanDate(2024, 8, 12),
        last: PlanDate(2024, 8, 20),
        dayWidth: 40,
      );
      expect(m.xForDate(PlanDate(2024, 8, 12)), 0);
    });

    test('dayWidth 이 0 이면 dateForX 는 firstDay (안전장치)', () {
      final m = _metrics(
        first: PlanDate(2024, 8, 1),
        last: PlanDate(2024, 8, 5),
        dayWidth: 0,
      );
      expect(m.dateForX(123.0), PlanDate(2024, 8, 1));
    });
  });

  group('dayColumnForX (히트 테스트/칸 판정)', () {
    final m = _metrics(
      first: PlanDate(2024, 8, 12),
      last: PlanDate(2024, 8, 20),
      dayWidth: 40,
    );

    test('칸 시작/중간/끝-ε 이 모두 같은 날', () {
      // 8/14 칸은 [80, 120). 시작 80, 중간 100, 끝-ε 119.99 모두 8/14.
      final day = PlanDate(2024, 8, 14);
      expect(m.dayColumnForX(80), day);
      expect(m.dayColumnForX(100), day);
      expect(m.dayColumnForX(119.999), day);
    });

    test('다음 칸 시작(120)은 다음 날(8/15)', () {
      expect(m.dayColumnForX(120), PlanDate(2024, 8, 15));
    });

    test('칸 뒤쪽 절반에서 dayColumnForX != dateForX (핵심 함정)', () {
      // 8/14 칸의 뒤쪽 절반: x=100~120. 여기서 dateForX(round)는 이미 8/15 로
      // 스냅되지만, dayColumnForX(floor)는 여전히 8/14 다.
      // x=110 (8/14 칸 뒤쪽 절반):
      expect(m.dayColumnForX(110), PlanDate(2024, 8, 14));
      expect(m.dateForX(110), PlanDate(2024, 8, 15)); // round → 다음 날
      // x=119.99 (8/14 칸 거의 끝):
      expect(m.dayColumnForX(119.99), PlanDate(2024, 8, 14));
      expect(m.dateForX(119.99), PlanDate(2024, 8, 15));
    });

    test('칸 앞쪽 절반에서는 dayColumnForX == dateForX', () {
      // x=85 (8/14 칸 앞쪽 절반): 둘 다 8/14.
      expect(m.dayColumnForX(85), PlanDate(2024, 8, 14));
      expect(m.dateForX(85), PlanDate(2024, 8, 14));
    });

    test('음수 x(범위 앞쪽)에서 floor 가 의도대로 동작', () {
      // x=-1 → floor(-1/40)=floor(-0.025)=-1 → 8/11.
      expect(m.dayColumnForX(-1), PlanDate(2024, 8, 11));
      // x=-40 → floor(-1)= -1 → 8/11.
      expect(m.dayColumnForX(-40), PlanDate(2024, 8, 11));
      // x=-41 → floor(-1.025)= -2 → 8/10.
      expect(m.dayColumnForX(-41), PlanDate(2024, 8, 10));
    });

    test('dayWidth 0 이면 firstDay (안전장치)', () {
      final mz = _metrics(
        first: PlanDate(2024, 8, 1),
        last: PlanDate(2024, 8, 5),
        dayWidth: 0,
      );
      expect(mz.dayColumnForX(123.0), PlanDate(2024, 8, 1));
    });
  });

  group('widthForRange inclusive', () {
    test('같은 날 시작·종료 → dayWidth 1개 분량(0이 아님)', () {
      final m = _metrics(
        first: PlanDate(2024, 8, 1),
        last: PlanDate(2024, 8, 31),
        dayWidth: 40,
      );
      expect(m.widthForRange(PlanDate(2024, 8, 12), PlanDate(2024, 8, 12)), 40);
    });

    test('3일 구간(8/12~8/14) → 3일치 폭', () {
      final m = _metrics(
        first: PlanDate(2024, 8, 1),
        last: PlanDate(2024, 8, 31),
        dayWidth: 40,
      );
      expect(m.widthForRange(PlanDate(2024, 8, 12), PlanDate(2024, 8, 14)), 120);
    });

    test('null 인 경우 → 0', () {
      final m = _metrics(
        first: PlanDate(2024, 8, 1),
        last: PlanDate(2024, 8, 31),
        dayWidth: 40,
      );
      expect(m.widthForRange(null, PlanDate(2024, 8, 14)), 0);
      expect(m.widthForRange(PlanDate(2024, 8, 12), null), 0);
    });
  });

  group('줌 레벨별 dayWidth 비례', () {
    test('dayWidth 가 바뀌면 x 도 그에 비례', () {
      final a = _metrics(
        first: PlanDate(2024, 8, 1),
        last: PlanDate(2024, 8, 31),
        dayWidth: 10,
      );
      final b = _metrics(
        first: PlanDate(2024, 8, 1),
        last: PlanDate(2024, 8, 31),
        dayWidth: 20,
      );
      final d = PlanDate(2024, 8, 11); // +10일
      expect(a.xForDate(d), 100);
      expect(b.xForDate(d), 200);
      expect(b.xForDate(d), a.xForDate(d) * 2);
    });

    test('enum dayWidth 은 0보다 큰 양수', () {
      for (final z in GanttZoomLevel.values) {
        expect(z.dayWidth, greaterThan(0));
      }
    });
  });

  group('오늘선 x', () {
    test('xForToday == xForDate(today)', () {
      final m = _metrics(
        first: PlanDate(2024, 8, 1),
        last: PlanDate(2024, 8, 31),
        dayWidth: 18,
      );
      final today = PlanDate(2024, 8, 16);
      expect(m.xForToday(today), m.xForDate(today));
    });
  });

  group('computeGanttMetrics 범위', () {
    test('노드 기간 + padding 으로 범위 계산', () {
      final today = PlanDate(2024, 8, 16);
      final nodes = [
        PlanNode(
          id: 'a',
          title: 'a',
          startDate: PlanDate(2024, 8, 10),
          endDate: PlanDate(2024, 8, 20),
        ),
      ];
      final m = computeGanttMetrics(
        visibleNodes: nodes,
        dayWidth: GanttZoomLevel.day.dayWidth,
        today: today,
        padDaysBefore: 7,
        padDaysAfter: 7,
      );
      expect(m.firstDay, PlanDate(2024, 8, 3)); // 8/10 - 7
      expect(m.lastDay, PlanDate(2024, 8, 27)); // 8/20 + 7
      expect(m.dayWidth, GanttZoomLevel.day.dayWidth);
    });

    test('날짜가 없으면 오늘 기준 기본 범위', () {
      final today = PlanDate(2024, 8, 16);
      final m = computeGanttMetrics(
        visibleNodes: [PlanNode(id: 'a', title: 'a')],
        dayWidth: GanttZoomLevel.day.dayWidth,
        today: today,
        padDaysBefore: 14,
        padDaysAfter: 30,
      );
      expect(m.firstDay, today.addDays(-14));
      expect(m.lastDay, today.addDays(30));
    });

    test('여러 노드의 전체 기간(min start ~ max end) + padding', () {
      final today = PlanDate(2024, 8, 16);
      final nodes = [
        PlanNode(
          id: 'a',
          title: 'a',
          startDate: PlanDate(2024, 8, 20),
          endDate: PlanDate(2024, 8, 25),
        ),
        PlanNode(
          id: 'b',
          title: 'b',
          startDate: PlanDate(2024, 8, 10),
          endDate: PlanDate(2024, 9, 5),
        ),
        PlanNode(
          id: 'c',
          title: 'c',
          startDate: PlanDate(2024, 8, 15),
          endDate: PlanDate(2024, 8, 18),
        ),
      ];
      final m = computeGanttMetrics(
        visibleNodes: nodes,
        dayWidth: GanttZoomLevel.day.dayWidth,
        today: today,
        padDaysBefore: 7,
        padDaysAfter: 7,
      );
      // min start = 8/10(b), max end = 9/5(b).
      expect(m.firstDay, PlanDate(2024, 8, 3)); // 8/10 - 7
      expect(m.lastDay, PlanDate(2024, 9, 12)); // 9/5 + 7
      expect(m.containsDate(today), isTrue); // 오늘이 범위 안.
    });

    test('노드 비어도 오늘 기준 기본 범위로 크래시 없음', () {
      final today = PlanDate(2024, 8, 16);
      final m = computeGanttMetrics(
        visibleNodes: const [],
        dayWidth: GanttZoomLevel.day.dayWidth,
        today: today,
      );
      expect(m.dayCount, greaterThan(0));
    });
  });

  group('computeGanttMetrics 열린 기간(종료일 미정)', () {
    test('열린 기간 노드가 있으면 lastDay 가 today 이후를 덮는다', () {
      // 과거에 시작하고 종료 미정인 항목: 막대는 오늘까지 그려지므로 타임라인
      // 끝이 오늘을 포함해야 한다(그렇지 않으면 막대 오른쪽이 잘려 나간다).
      final today = PlanDate(2024, 8, 16);
      final nodes = [
        PlanNode(
          id: 'a',
          title: 'a',
          startDate: PlanDate(2020, 1, 1),
          // endDate == null (열린 기간)
        ),
      ];
      final m = computeGanttMetrics(
        visibleNodes: nodes,
        dayWidth: GanttZoomLevel.day.dayWidth,
        today: today,
        padDaysBefore: 7,
        padDaysAfter: 7,
      );
      // today 가 maxEnd 후보에 들어갔으므로 lastDay 는 today + padDaysAfter.
      expect(m.containsDate(today), isTrue);
      expect(m.lastDay, today.addDays(7));
    });

    test('확정 종료일이 today 보다 뒤면 그 값이 maxEnd 로 우선한다', () {
      // 열린 기간 노드가 섞여 있어도, 더 먼 확정 종료일이 있으면 그쪽이 우선.
      final today = PlanDate(2024, 8, 16);
      final nodes = [
        PlanNode(
          id: 'a',
          title: 'a',
          startDate: PlanDate(2024, 8, 1),
          // endDate == null (열린 기간)
        ),
        PlanNode(
          id: 'b',
          title: 'b',
          startDate: PlanDate(2024, 8, 10),
          endDate: PlanDate(2024, 12, 31),
        ),
      ];
      final m = computeGanttMetrics(
        visibleNodes: nodes,
        dayWidth: GanttZoomLevel.day.dayWidth,
        today: today,
        padDaysBefore: 7,
        padDaysAfter: 7,
      );
      // maxEnd = 2024-12-31 (today 보다 뒤). lastDay = 그것 + 7.
      expect(m.lastDay, PlanDate(2025, 1, 7));
    });

    test('열린 기간 노드 단독이면 firstDay 는 start - padding 그대로', () {
      final today = PlanDate(2024, 8, 16);
      final nodes = [
        PlanNode(
          id: 'a',
          title: 'a',
          startDate: PlanDate(2024, 8, 10),
        ),
      ];
      final m = computeGanttMetrics(
        visibleNodes: nodes,
        dayWidth: GanttZoomLevel.day.dayWidth,
        today: today,
        padDaysBefore: 7,
        padDaysAfter: 7,
      );
      // minStart 는 start, maxEnd 는 today. first = start - 7, last = today + 7.
      expect(m.firstDay, PlanDate(2024, 8, 3));
      expect(m.lastDay, PlanDate(2024, 8, 23));
    });
  });

  group('헤더 셀 생성', () {
    test('일 단위: 매일 1칸, dayCount 와 일치', () {
      final m = _metrics(
        first: PlanDate(2024, 8, 1),
        last: PlanDate(2024, 8, 10),
        dayWidth: 40,
      );
      final cells = buildHeaderCells(m);
      expect(cells.length, 10);
      expect(cells.first.date, PlanDate(2024, 8, 1));
      expect(cells.last.date, PlanDate(2024, 8, 10));
      // 8/1 은 월 시작 → 강조.
      expect(cells.first.emphasize, isTrue);
    });

    test('주 단위: 첫 주의 월요일에서 시작', () {
      // 2024-08-07(수) ~ 2024-08-20(화). startOfWeek(8/7)=8/5(월).
      final m = _metrics(
        first: PlanDate(2024, 8, 7),
        last: PlanDate(2024, 8, 20),
        dayWidth: 18,
      );
      final cells = buildHeaderCells(m);
      expect(cells.first.date, PlanDate(2024, 8, 5));
    });

    test('월 단위: 매월 1일 칸', () {
      final m = _metrics(
        first: PlanDate(2024, 8, 10),
        last: PlanDate(2024, 10, 15),
        dayWidth: 5,
      );
      final cells = buildHeaderCells(m);
      expect(cells.first.date, PlanDate(2024, 8, 1));
      expect(cells.any((c) => c.date == PlanDate(2024, 9, 1)), isTrue);
      expect(cells.any((c) => c.date == PlanDate(2024, 10, 1)), isTrue);
    });
  });

  group('weekendDayOffsets', () {
    test('일 단위에서만 동작, 토/일 오프셋 반환', () {
      // 2024-08-05(월) ~ 2024-08-11(일). 토=8/10(offset5), 일=8/11(offset6).
      final m = _metrics(
        first: PlanDate(2024, 8, 5),
        last: PlanDate(2024, 8, 11),
        dayWidth: 40,
      );
      final offsets = weekendDayOffsets(m);
      expect(offsets, containsAll(const [5, 6]));
    });

    test('일 단위가 아니면 빈 목록', () {
      final m = _metrics(
        first: PlanDate(2024, 8, 5),
        last: PlanDate(2024, 8, 11),
        dayWidth: 18,
      );
      expect(weekendDayOffsets(m), isEmpty);
    });
  });
}

void _zoomOutLevelsTests() {
  group('축소 단계(분기/년) 헤더 셀', () {
    test('분기 단위는 1/4/7/10월 1일마다 셀을 만들고 "YYYY Qn" 으로 라벨링한다', () {
      final m = GanttMetrics(
        firstDay: PlanDate(2026, 2, 15),
        lastDay: PlanDate(2026, 11, 20),
        dayWidth: GanttZoomLevel.quarter.dayWidth,
      );
      final cells = buildHeaderCells(m);
      // 2/15 가 속한 분기(Q1=1/1)부터 11/20 이 속한 분기(Q4=10/1)까지 4개.
      expect(cells.map((c) => c.label).toList(),
          ['2026 Q1', '2026 Q2', '2026 Q3', '2026 Q4']);
      // 각 셀의 시작일은 분기 첫 달 1일.
      expect(cells.map((c) => c.date.month).toList(), [1, 4, 7, 10]);
      // Q1(1~3월) = 31+28+31 = 90일 (2026 은 평년).
      expect(cells.first.dayCount, 90);
    });

    test('년 단위는 1월 1일마다 셀을 만들고 연도로 라벨링한다', () {
      final m = GanttMetrics(
        firstDay: PlanDate(2026, 6, 1),
        lastDay: PlanDate(2028, 3, 1),
        dayWidth: GanttZoomLevel.year.dayWidth,
      );
      final cells = buildHeaderCells(m);
      expect(cells.map((c) => c.label).toList(), ['2026', '2027', '2028']);
      expect(cells[0].dayCount, 365);
      expect(cells[1].dayCount, 365);
      // 2028 은 윤년.
      expect(cells[2].dayCount, 366);
    });

    test('축소할수록 하루 폭이 좁아진다(일 > 주 > 월 > 분기 > 년)', () {
      final widths =
          GanttZoomLevel.values.map((z) => z.dayWidth).toList();
      for (var i = 1; i < widths.length; i++) {
        expect(widths[i], lessThan(widths[i - 1]),
            reason: '${GanttZoomLevel.values[i].label} 는 앞 단계보다 좁아야 한다');
      }
    });

    test('년 단위에서는 폰 화면(400px) 에 최소 1년 이상이 들어온다', () {
      // 축소를 더 하고 싶다는 요구의 핵심 — 한 화면에 담기는 기간이 실제로 늘어야 한다.
      const viewWidth = 400.0;
      final daysVisible = viewWidth ~/ GanttZoomLevel.year.dayWidth;
      expect(daysVisible, greaterThan(365));
      // 월 단위(5px/일) 에서는 80일 남짓밖에 안 보였다.
      expect(viewWidth ~/ GanttZoomLevel.month.dayWidth, lessThan(100));
    });
  });
}
