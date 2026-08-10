# PlanBook — 설계 문서 (DESIGN.md)

> **PlanBook**: 계층적 장기 목표를 한 번 계획해 두면, 날짜를 기준으로 **오늘 무엇을 해야 하는지**가 자동으로 정리되는 계획 전용 앱.
>
> 본 문서는 1단계(데이터 모델 · 도메인 로직 · 영속화 · 단위 테스트 · 최소 디버그 UI) 설계를 정의한다.

---

## 1. 전체 아키텍처

### 1.1 레이어 구성

```
┌─────────────────────────────────────────────┐
│  UI Layer (ui/)                              │   최소 디버그 화면만 (1단계)
│   - app.dart / debug/plan_debug_screen.dart  │   2~4단계에서 Gantt/필터/일간뷰 추가
├─────────────────────────────────────────────┤
│  State / Mutation Layer (data/)             │
│   - plan_store.dart  (단일 mutation 경로)    │   ChangeNotifier + autosave + Undo 확장점
│   - plan_repository.dart (추상 인터페이스)   │
│   - json_plan_repository.dart (JSON 구현)    │   원자적 쓰기
├─────────────────────────────────────────────┤
│  Domain Layer (domain/)                     │
│   - plan_node.dart (PlanNode 모델)           │   계층의 모든 단계가 같은 타입
│   - plan_enums.dart (Priority, NodeKind)     │
│   - plan_tree.dart (조회/이동/삭제/순환검사)  │   무결성 규칙의 핵심
│   - plan_rollup.dart (유효값 계산)           │   원본값 보존
│   - plan_query.dart (날짜기반 조회)          │   일간/주간/월간 뷰의 데이터 소스
├─────────────────────────────────────────────┤
│  Core Layer (core/)                         │
│   - date/plan_date.dart  (날짜 단일 출처)    │   timezone/DST 버그 원천 차단
│   - ids.dart             (uuid v4)          │
└─────────────────────────────────────────────┘
```

**핵심 제약 3가지** (반드시 지킨다):
1. **날짜 계산은 한 곳** (`core/date/plan_date.dart`) — 다른 파일은 `DateTime.now()` / `DateTime.difference()` 를 직접 쓰지 않는다.
2. **mutation 단일 경로** (`data/plan_store.dart` 의 `_mutate`) — 모든 변경(추가/수정/이동/재정렬/삭제)은 이 함수를 통과한다.
3. **저장소 인터페이스 분리** (`PlanRepository`) — 구현(JSON)이 뒤에 숨고, 향후 sqflite 등으로 교체 가능.

### 1.2 폴더 구조 / 파일 목록

```
PlanBook/
├── DESIGN.md                      # 본 문서
├── pubspec.yaml                   # path_provider, uuid, intl
├── analysis_options.yaml
├── .gitignore
├── lib/
│   ├── main.dart                  # 진입점 (path_provider로 저장 dir 주입, lifecycle flush)
│   ├── core/
│   │   ├── date/plan_date.dart    # PlanDate, 정규화, 일수, 겹침, 주/월 경계, 픽셀→일수
│   │   └── ids.dart               # newId() = uuid v4
│   ├── domain/
│   │   ├── plan_enums.dart        # Priority, NodeKind
│   │   ├── plan_node.dart         # PlanNode (immutable + copyWith + toJson/fromJson)
│   │   ├── plan_tree.dart         # 트리 인덱스/조회/이동/재정렬/삭제/순환검사
│   │   ├── plan_rollup.dart       # RollupResult + computeRollup (원본값 미변경)
│   │   └── plan_query.dart        # coversDate/overlapsRange, 일간/주간/월간 조회
│   ├── data/
│   │   ├── plan_repository.dart   # PlanSnapshot + PlanRepository 추상
│   │   ├── json_plan_repository.dart  # JSON 파일 원자적 쓰기 구현
│   │   └── plan_store.dart        # PlanStore: 단일 mutation 경로 + autosave + flush
│   └── ui/
│       ├── app.dart               # MaterialApp (테마, PlanBook)
│       └── debug/
│           └── plan_debug_screen.dart  # 1단계 최소 화면 (들여쓰기 트리 + 샘플 생성)
├── test/
│   ├── plan_date_test.dart
│   ├── plan_tree_test.dart
│   ├── plan_rollup_test.dart
│   ├── plan_query_test.dart
│   └── plan_repository_test.dart
├── android/                       # Android 타깃
└── windows/                       # Windows 타깃
```

> iOS / web / linux / macos 폴더는 생성하지 않는다(요구사항).

### 1.3 데이터 흐름

- **읽기**: `UI → PlanStore.tree → PlanTree`(조회) / `plan_query` / `plan_rollup` (모두 순수 함수, 원본값 변경 없음)
- **쓰기**: `UI → PlanStore.addNode/moveNode/.../deleteCascade → _mutate(트리 조작 + dirty + autosave 예약 + notifyListeners) → Timer(400ms) → JsonPlanRepository.save (원자적 쓰기)`
- **종료/백그라운드**: `didChangeAppLifecycleState → PlanStore.flush` (보류 저장 즉시 기록)

---

## 2. 데이터 모델 정의

### 2.1 PlanNode (계층의 모든 단계를 표현하는 단일 타입)

> **설계 결정**: 목표/서브목표/작업/하위작업을 별도의 `Goal`/`SubGoal`/`Task` 클래스로 나누지 **않**는다. (별도 타입은 곧 깊이 제한) 모두 `PlanNode` 이고 `parentId` 로 계층을 만든다. 깊이 제한 없음.

| 필드          | 타입              | nullable | 기본값          | 의미 / 비고                                                                |
|---------------|-------------------|----------|----------------|---------------------------------------------------------------------------|
| `id`          | `String`          | 아니오   | —              | uuid v4. **절대 재생성/재할당 금지**. 영구 식별자.                          |
| `parentId`    | `String?`         | 예       | `null`         | null = 최상위(프로젝트/목표 루트).                                          |
| `title`       | `String`          | 아니오   | `''`           | 제목.                                                                      |
| `startDate`   | `PlanDate?`       | 예       | `null`         | 시작일(시간 없음). null=미정.                                              |
| `endDate`     | `PlanDate?`       | 예       | `null`         | 종료일(시간 없음). **inclusive = 당일 포함**.                              |
| `progress`    | `double`          | 아니오   | `0.0`          | 진행률 `0.0~1.0`. (0..1 double 로 통일)                                    |
| `isDone`      | `bool`            | 아니오   | `false`        | 완료 여부. rollup 노드면 파생값(자식 전부 완료시 true)                     |
| `priority`    | `Priority`        | 아니오   | `none`         | enum: none/low/medium/high                                                 |
| `category`    | `String?`         | 예       | `null`         | 카테고리/프로젝트 구분(예: "업무").                                         |
| `tags`        | `List<String>`    | 아니오   | `const []`     | 태그.                                                                      |
| `memo`        | `String?`         | 예       | `null`         | 메모.                                                                      |
| `estimate`    | `num?`            | 예       | `null`         | 예상 작업량. rollup 가중치에도 사용.                                        |
| `actual`      | `num?`            | 예       | `null`         | 실제 작업량.                                                               |
| `sortOrder`   | `double`          | 아니오   | `0.0`          | 같은 부모 아래 형제 순서. double → 두 값 사이 끼워넣기 시 재색인 최소화.   |
| `isCollapsed` | `bool`            | 아니오   | `false`        | 트리 접기/펼치기(UI 영속 상태).                                            |
| `nodeKind`    | `NodeKind`        | 아니오   | `project`      | enum: **project**(현재 사용) / quantity / recurring(예약, §9)             |
| `autoRollup`  | `bool`            | 아니오   | `true`         | true 면 start/end/progress/isDone 을 자식으로부터 계산(§7).                |

- `PlanNode` 는 **immutable** 이며 `copyWith` 로만 수정. (단, nullable 필드인 `parentId/category/memo/estimate/actual` 은 sentinel 패턴으로 "명시적 null 지우기"와 "변경 없음"을 구분한다.)
- `id` 는 한 번 할당되면 절대 바뀌지 않는다(이동/재정렬/복사 모두 id 보존).

### 2.2 보조 타입

- `Priority` (`plan_enums.dart`): `none / low / medium / high`. JSON 직렬화는 `name` 문자열. 알 수 없는 값 → `none`.
- `NodeKind`: `project / quantity / recurring`. 1단계는 `project` 만 사용.
- `PlanSnapshot` (`plan_repository.dart`): `{ schemaVersion: int, nodes: List<PlanNode> }`. 파일 최상위 구조.
- `RollupResult` (`plan_rollup.dart`): `{ startDate, endDate, progress, isDone, computedFromChildren }`. 계산된 **유효값**. 노드 원본값과 별개.
- `PlanDate` (`core/date/plan_date.dart`): `year/month/day` 불변값. 시간 성분 없음. §3 참고.

---

## 3. 날짜 처리 정책

> **버그 다발 지점**. 모든 날짜 계산은 `core/date/plan_date.dart` 한 곳에 모인다.

### 3.1 핵심 원칙
- 시간 개념이 없는 **달력 날짜**만 다룬다. `PlanDate(year, month, day)` 불변값.
- **UTC 변환을 하지 않는다.** 저장 포맷은 ISO `YYYY-MM-DD` 고정.
- `DateTime` 을 직접 써야 하면 반드시 `normalizeDateTime(dt)` (year/month/day 만 남기고 시=0, `isUtc=false`) 로 정규화.
- 앱 전체에서 `DateTime.now()` 를 직접 부르지 않는다. "오늘"은 `PlanStore` 가 주입받은 `DateTimeProvider` 로부터 얻고(`PlanStore.today`), 질의 함수(`tasksCoveringDate` 등)는 **명시적 `PlanDate` 만 받는 순수 함수** → 테스트에서 고정 날짜 주입 가능.

### 3.2 일수 계산 (DST/시간 성분 영향 차단)
- `DateTime.difference().inDays` 는 DST/시간 성분으로 오차가 날 수 있으므로 사용하지 않는다.
- 대신 **Julian Day Number(JDN)** 정수 기반: `PlanDate.julianDayNumber`. 일수 차이 = `b.julianDayNumber - a.julianDayNumber` (순수 정수 연산, 시간대 무관).
- `daysBetween(a,b)`, `addDays(delta)`, `inclusiveDayCount(start,end)` 모두 JDN 기반.
- 테스트로 증명: 월말/월초, 연말연시(12/31→1/1), 윤년(2024-02-29 존재/2023-02-29 거부), 1년 스팬(2024는 366일) 경계.

### 3.3 Gantt 드래그 픽셀→일수 변환 (1단계엔 UI 없지만 함수/테스트는 구현)
- 한 곳에서 정의: `int dayDeltaFromPixels(double dx, double dayWidth) => (dx / dayWidth).round();`
  - 0.4일 → 0, 0.6일 → 1, -0.6일 → -1. (Dart `round()` 는 half-away-from-zero)
  - `dayWidth <= 0` → 0 (안전장치).
- 기간 길이 보존 이동: `shiftRange(start, end, dayDelta)` → 양끝을 같은 delta 만큼 이동. `(8/12~8/16, +2) = (8/14~8/18)`, `inclusiveDayCount` 보존(테스트로 검증).

### 3.4 기간 겹침 판정 (일간/주간/월간 뷰가 모두 사용)
- 노드 기반(도메인): `bool coversDate(PlanNode n, PlanDate d)` — `d.isWithin(n.startDate, n.endDate)`, 양끝 inclusive.
- 노드 기반: `bool overlapsRange(PlanNode n, PlanDate from, PlanDate to)` — `[start,end]` ∩ `[from,to]` 겹침(inclusive).
- 원시(코어): `dateWithin(date, start, end)`, `overlapsRange(s1,e1,s2,e2)` — null 한쪽은 무한, 둘 다 null이면 항상 겹침/포함.
- inclusive 의미: `start == d == end` 도 참. 끝점 접촉(8/10~8/15 와 8/15~8/20)도 겹침.

### 3.5 주/월 경계
- **주 시작 = 월요일**(`kWeekStartWeekday = DateTime.monday`). `startOfWeek` / `endOfWeek`.
- 월 경계: `startOfMonth`(1일) / `endOfMonth`(다음 달 1일 - 1일, 윤년 2월 정확).
- 테스트: 일요일(2024-01-07)→직전 월요일(01-01), 월요일(2024-01-01)→자기 자신, 연도 경계 주(2023-01-01 일요일 → 2022-12-26).

---

## 4. 영속화(저장) 방식

### 4.1 방식 / 파일 위치
- **로컬 JSON 파일**(신규 라이브러리 최소화, Windows·Android 동일 동작, 데이터가 작음).
- 위치: `path_provider` 의 `getApplicationSupportDirectory()` 하위
  `<appSupport>/PlanBook/plan_store.json` (디렉터리 없으면 생성).
- 테스트에서는 임시 디렉터리(`Directory.systemTemp`)를 `JsonPlanRepository(directory:...)` 로 주입 → I/O 경로 주입 가능.

### 4.2 저장 트리거
- 모든 변경은 `PlanStore._mutate` 단일 경로 통과 → `dirty = true` → **debounce 400ms** 후 자동 저장(`Timer`).
- 앱 일시정지/비활성/분리(`didChangeAppLifecycleState`) 시 `PlanStore.flush()` 즉시 기록(Timer 취소 후 동기 저장).
- 저장 실패 시 `dirty` 복구 → 다음 변경/flush 시 재시도.

### 4.3 원자적 쓰기
1. `<fileName>.tmp` 에 전체 JSON 쓰기(flush).
2. `.tmp` 를 실제 파일명으로 `rename` (같은 디렉터리 rename 은 Win32/POSIX 모두 원자적).
   - Dart 의 `File.rename` 은 대상 파일이 이미 존재해도 예외 없이 **덮어쓴다**.
   - **주의**: 과거에는 rename 전에 기존 파일을 `delete()` 했으나, 이는 delete와 rename
     사이에 프로세스가 죽으면 실제 파일이 없는 상태가 되어 **데이터가 소실**되는
     치명적 버그였다. rename 한 번으로 원자적 교체가 보장되므로 delete() 는 하지 않는다.
- 쓰다 죽어도 기존 파일은 손상되지 않는다(임시 파일만 남고 원본은 보존).
- 복구 정책: `load()` 시 본 파일이 없거나 손상된 경우, 같은 디렉터리의 `.tmp` 가
  유효한 JSON 이면 그것으로 복구한 뒤 정상 파일로 승격(rename)한다. 본 파일이
  정상일 때는 `.tmp` 를 건드리지 않는다(정상 경로 비용 없음).

### 4.4 포맷 / 복구 정책
- 최상위에 `schemaVersion` 필드(현재 `1`). 향후 마이그레이션 기준.
- 알 수 없는 필드는 **무시**(forward-compat). 알려진 필드만 파싱.
- 파일이 없거나 비어있으면 → 빈 상태(`load` 가 `null` 반환).
- JSON 손상(`FormatException`) → `null` (예외 X, 앱 크래시 X).
- 개별 노드 파싱 실패 → 해당 항목만 건너뛰고 나머지는 로드.
- `PlanRepository` 추상 인터페이스 뒤에 구현이 숨겨, 향후 `sqflite` 등으로 교체 가능.

---

## 5. 부모 삭제 시 자식 처리 정책

> **정책 결정**: 기본 = **cascade 삭제**(자손 전부 삭제). 보조 = **promote 승격**(자식을 조부모로).

### 5.1 cascade (기본)
- `PlanTree.deleteCascade(id)` / `PlanStore.deleteCascade(id)`.
- 반환값 = 삭제된 노드 수(자기 자신 포함) → **UI 확인창**에서 "이 항목과 하위 N개가 삭제됩니다" 표시용.
- 삭제 전 `descendantCount(id)` 로 자손 수만 미리 셀 수도 있다.
- **무결성**: `subtree(id)` 를 수집해 한 번에 제거 → 다른 가지는 영향받지 않음(테스트로 검증).

### 5.2 promote (보조)
- `PlanTree.deletePromote(id)` / `PlanStore.deletePromote(id)`.
- 대상 노드만 삭제하고, 자식들을 **조부모(대상의 기존 부모) 아래**로 옮김. 상대 순서 유지 + 원래 위치에 끼워넣기.
- 삭제 수 = 항상 1.

### 5.3 선택 기준(문서화)
- 일반적인 "프로젝트/목표 삭제" → cascade 권장(하위 계획 전체 제거).
- "중간 폴더만 없애고 하위는 유지" → promote.

---

## 6. 필터가 켜진 상태에서 Drag 시 잘못된 위치 이동 방지 설계

> **핵심 문제**: 필터/접기 상태에서 화면에 보이는 항목의 **화면 index** 와 실제 **형제 index** 가 다르다. index 기반 이동(`move(fromIndex, toIndex)`)은 반드시 버그를 낸다.

### 6.1 설계 (ID 기반)
- 모든 이동/재정렬 API는 **대상 노드 ID + 기준 형제 ID + before/after 위치**로 표현한다.
  ```
  insertAt(id, { newParentId, required referenceSiblingId, required InsertPosition position })
  PlanStore.reorderSibling(id, { referenceSiblingId, position, newParentId })
  ```
- `InsertPosition` = `before | after`.
- `referenceSiblingId` 는 `newParentId` 의 **기존 자식**이어야 한다(위반 시 `PlanTreeException`, 트리 미변경).
- 필터가 어떻게 켜져 있든 **항상 실제 트리의 형제 ID**를 사용하므로 위치 오류가 발생하지 않는다.

### 6.2 부작용 방지
- 순환 참조(`wouldCreateCycle`) 이동은 사전 검사 후 거부(§참고: `plan_tree`).
- `referenceSiblingId == id` 인 경우(자기 자신을 기준) 거부.
- 재정렬 후 해당 부모의 `sortOrder` 를 `0,1,2,...` 로 재부여하여 결정적(deterministic) 정렬 보장.
- 모든 변경은 단일 mutation 경로(`PlanStore._mutate`)를 거쳐 dirty/autosave/알림이 정확히 한 번 발생.

---

## 7. Rollup 규칙 (부모 기간/진행률을 자식으로부터 계산)

> **원본값 보존 원칙(핵심)**: rollup 결과는 별도의 `RollupResult` 로 반환되며, **노드의 저장된 원본값을 절대 덮어쓰지 않는다**. UI 는 rollup 결과를 "유효값"으로만 읽어 표시한다.

### 7.1 적용 조건
- `PlanNode.autoRollup == true` **이고** 자식이 존재할 때 → 자식 기반 계산.
- 그 외(자식 없음 또는 `autoRollup==false`) → 노드 자신의 저장값을 그대로 사용.

### 7.2 기간(유효 start/end)
- `유효 startDate = min(자식들 유효 startDate)`
- `유효 endDate = max(자식들 유효 endDate)`
- 날짜가 하나도 없으면 start/end 모두 `null`.
- 자식이 autoRollup 이면 **재귀** 계산.

### 7.3 진행률(유효 progress)
- **모든** 자식이 `estimate`(non-null) 를 가지고 estimate 합 > 0 이면 → **estimate 가중평균**:
  `Σ(자식 유효 progress × 자식 estimate) / Σ(자식 estimate)`
- 그렇지 않으면 → **단순평균**: `mean(자식 유효 progress)`.
- 결과는 `[0.0, 1.0]` 로 clamp.

### 7.4 완료(유효 isDone)
- **모든** 자식의 유효 `isDone == true` → 부모 유효 `isDone = true`.
- (파생값. 노드의 저장 `isDone` 은 사용자가 직접 설정한 원본값으로 보존.)

### 7.5 원본값 보존 검증
- 자식이 있을 때: rollup 결과는 자식 기반이지만, 노드의 저장 `startDate/endDate/progress/isDone` 은 그대로 유지(테스트 `stored original values not corrupted` 로 검증).
- 일간 뷰는 **leaf 작업**(자식 없음)만 보므로, leaf 는 유효값==저장값 이고 rollup 영향을 받지 않는다.

---

## 8. Undo 확장 지점 (지금은 미구현, 설계만)

- **단일 mutation 경로** `PlanStore._mutate<T>(MutationKind kind, T Function() action)` 가 Undo hook 이다.
- 현재: `action()` 실행 → dirty → autosave 예약 → `notifyListeners()`.
- 향후 추가(계획):
  - `_mutate` 진입 시 "변경 전/후 스냅샷" 또는 "역연산 command" 를 undo stack 에 push.
  - `MutationKind` enum(`add/update/remove/move/reorder/clear/sample`) 으로 각 종류별 역연산 매핑.
  - `undo()` / `redo()` 가 동일한 `_mutate` 경로를 통해(단, 히스토리 기록 없이) 트리를 복원.
- **구현 변경 최소화**: 도메인(`PlanTree`)은 그대로, store 에 stack 만 추가하면 됨.

---

## 9. 수량형(quantity) / 반복형(recurring) 확장 지점

> 1단계는 `nodeKind == project` 만 사용. 필드만 예약.

### 9.1 quantity (수량형)
- `PlanNode.nodeKind = quantity`. 예: "총 100페이지", "총 50개".
- `estimate` = 목표 총량, `actual` = 현재 누적 실적.
- **분배 전략(2단계 이후)**: 기간 `[startDate, endDate]` 을 일수로 나눠 일일 할당량을 산출 → 일간 뷰에서 "오늘 N페이지" leaf 를 **가상으로 생성**하여 표시(저장 트리에 실제 노드를 만들지 않고 query 단에서 파생).
- rollup 확장: quantity 노드의 진행률 = `actual / estimate`.
- 확장 포인트: `plan_query` 에 `tasksCoveringDate` 가 노드의 `nodeKind` 에 따라 분기 → quantity 분배 leaf 추가. (현재는 project leaf 만.)

### 9.2 recurring (반복형)
- `PlanNode.nodeKind = recurring`. 예: "매주 월요일", "매일 30분".
- 반복 규칙 필드는 아직 모델에 없음(필요시 `recurrenceRule` 추가 → 마이그레이션 시 `schemaVersion` 증가).
- **분배 전략**: `[from, to]` 범위 내 반복 발생일을 산출(`plan_date` 의 `startOfWeek`/요일 계산 활용) → 일간 뷰에 가상 leaf 추가.
- 확장 포인트: 동일하게 `plan_query` 의 `nodeKind` 분기.

### 9.3 공통 가상 leaf 모델 (계획)
- 자동 생성 항목과 사용자 직접 입력(free note) 항목을 **시각적으로 명확히 구분** → `PlanNode` 에 `source` 필드(`planned`/`manual`) 또는 별도 뷰 모델로 표현(2단계 결정).

---

## 10. 로드맵 (2~4단계)

### 2단계 — Gantt 렌더링 + 트리 UI
- 프로젝트 계획 페이지: 좌측 트리 패널 + 우측 타임라인 Gantt(직접 구현, 라이브러리 X).
- Gantt bar 렌더링: 노드 기간 → 픽셀 매핑(`dayDeltaFromPixels` 역방향), 좌표→날짜 변환.
- **반응형**: Fold/화면 폭 변화 대응(panes 비율, Gantt 폭 조정).
- 트리 위젯: 접기/펼치기, 깊이 들여쓰기, 우클릭/롱프레스 컨텍스트 메뉴.

### 3단계 — 인터랙션
- Gantt bar **좌우 드래그** = 일정 이동, **양 끝 드래그** = 시작/종료일 변경(`shiftRange` 로 기간 보존).
- 트리 항목 **Drag&Drop** 순서 변경 + 다른 부모로 계층 이동(`insertAt`/`reorderSibling` ID 기반).
- **필터**(프로젝트/카테고리/태그/진행상태/기간/우선순위 + 오늘·이번주·이번달·전체 빠른 필터) — §6 설계로 안전.

### 4단계 — 일간/주간/월간 뷰 + 자동 반영
- 일간 뷰(핵심): 오늘 `PlanDate` 의 leaf 작업 자동 추출(`tasksCoveringDate`).
  - 계획 자동 항목 vs free note **시각 구분**.
  - 자동 항목 체크 → 계획 트리의 해당 작업 `isDone/progress` 반영.
- 주간/월간 뷰(`tasksForWeek`/`tasksForMonth`).
- quantity/recurring 자동 분배 leaf 표시(§9).
- Undo/Redo(§8).

---

## 부록: 1단계 완료 기준 검증
- `flutter analyze`: **에러 0** (warning/info 0 도달).
- `flutter test`: **95개 전부 통과** (date / tree / rollup / query / repository).
- UI: 최소 디버그 화면만(들여쓰기 트리 + 오늘 leaf 미리보기 + 샘플 생성/전체 삭제). Gantt/드래그/필터/일간뷰는 미구현(정상).

---

# 11. 4엔티티 모델 확장 (Project / Task / Tag / AppSettings)

## 11.1 Project 는 목표가 아니라 최상위 분류다

    Project(업무)                          <- Projects 화면의 카드 단위
      └ Task(Complex Filter 완성)          <- 트리 루트 = 목표(Goal)
          └ Task(알고리즘 구현)             <- 서브목표
              └ Task(Complex BPF 계수 생성) <- 실행 작업

- `PlanNode.parentId`  : **Task 계층**. 깊이 제한 없음. 목표/서브목표/작업/하위작업이
  전부 같은 `PlanNode` 타입이다(타입을 나누면 깊이가 고정된다).
- `PlanNode.projectId` : **소속 분류**. 필터/집계용 비정규화 필드.

둘을 혼동하지 말 것. 트리를 거슬러 올라가 프로젝트를 찾는 방식이 아니라,
각 Task 가 자기 projectId 를 직접 들고 있다(필터가 O(1)).

## 11.2 TaskStatus 4상태와 isDone 파생

    enum TaskStatus { notStarted, inProgress, done, onHold }

- **`isDone` 은 저장 필드가 아니다.** `bool get isDone => status == TaskStatus.done`
  파생 getter다. `copyWith` 에도 `isDone` 파라미터가 없다 — 완료는 `status` 로만 바꾼다.
- **`onHold`(보류)는 완료가 아니다.** rollup 의 "모든 자식 완료 → 부모 완료" 판정은
  `status == done` 기준으로만 이뤄지므로, 보류 자식이 하나라도 있으면 부모는 미완료다.
- `RollupResult.isDone` 은 계산된 유효 완료값이며 원본 노드 값을 덮어쓰지 않는다.

## 11.3 삭제 정책

| 대상 | 정책 |
|---|---|
| Project | **Task 를 삭제하지 않는다.** 소속 Task 의 `projectId` 만 null 로(미분류). 분류 하나를 지웠다고 작업이 사라지면 안 된다. |
| Tag | 해당 tag id 를 모든 `Task.tagIds` 에서 제거한다. |
| Task(부모) | 기존 정책 유지 — cascade(기본) / promote(자식 승격) 이원화. |

## 11.4 기본 Project seed

- 최초 빈 데이터일 때 `업무 / 연구 / 건강 / 개인 / 기타` 5개를 **1회만** 시드한다.
- `AppSettings.seededDefaultProjects` 플래그로 제어한다.
- **사용자가 지운 기본 프로젝트는 재실행해도 되살아나지 않는다.**

## 11.5 schemaVersion 마이그레이션 (v1 -> v2)

`lib/data/plan_migration.dart` 가 담당한다. **저장 로직(원자적 rename, .tmp 복구)은
건드리지 않는다** — 파싱된 payload 를 변환할 뿐이다.

| v1 | v2 |
|---|---|
| `category` 문자열 | 같은 이름 Project 검색 → 없으면 생성 → `projectId` 연결 |
| `tags` 문자열 배열 | 같은 이름 Tag 검색 → 없으면 생성 → `tagIds` 연결 |
| `isDone == true` | `TaskStatus.done` |
| `isDone == false && progress > 0` | `TaskStatus.inProgress` |
| `isDone == false && progress == 0` | `TaskStatus.notStarted` |

같은 이름은 하나의 Project/Tag 로 합쳐진다. 알 수 없는 필드는 무시하고,
깨진 노드는 그 항목만 건너뛴다(전체 로드를 죽이지 않는다).

## 11.6 저장 구조

**모든 데이터는 하나의 스냅샷에 담겨 하나의 파일로 저장된다.**
엔티티가 늘었다고 별도 파일/별도 DB/별도 저장 경로를 만들지 않는다.

    { schemaVersion, nodes[], projects[], tags[], settings }

Project/Tag/Settings CRUD 도 전부 기존 단일 mutation 경로
(`_mutate` → dirty → debounce autosave → 기존 저장 경로)를 통과한다.
이 경로를 우회하는 save 함수는 만들지 않는다 — 여기가 향후 Undo 확장 지점이다.

## 11.7 AppShell

- 화면 4개: Today / Gantt / Calendar / Projects
- **기본 진입 화면은 Today.** `AppSettings.lastScreen` 으로 재실행 시 복원하되,
  값이 없을 때의 기본값은 항상 Today 다.
- `width >= kTwoPaneBreakpoint(720)` → `NavigationRail`, 미만 → `NavigationBar`.
  (기존 상수를 재사용한다)
- `IndexedStack` 으로 화면 전환 시 각 화면 상태를 보존한다.
- 테마는 `AppSettings.themeMode` 를 따른다.
- Today / Calendar 는 아직 placeholder. Projects 는 시드 확인용 목록만.

## 11.8 지연(overdue)은 저장하지 않는다

"지연된 작업" 은 저장 필드가 아니라 계산이다:
`endDate < today && status != done`.
화면별로 날짜를 복제 저장하지 않는다 — Today/Calendar/Gantt 는 모두 같은 Task 데이터를 쓴다.

## 11.9 테스트에서 주의할 점

`testWidgets` 본문은 fake-async 존이라 **실제 디스크 I/O(`flush`/`load`)가 완료되지
않고 멈춘다.** 위젯 테스트 안에서 실제 저장/로드를 해야 하면 반드시
`tester.runAsync()` 안에서 호출할 것. (`setUp` 은 정상 존이라 그대로 써도 된다)

---

# 12. Gantt Project 선택기 / status·milestone 시각화 / effective 기간

## 12.1 새 파일

- `lib/domain/effective_dates.dart` — [computeEffectiveDateRange]. rollup 과
  **독립된 개념**이다: autoRollup 값과 무관하게, 노드 자신에게 날짜가 전혀 없을
  때만 자손 전체(그랜드칠드런 포함, 재귀)에서 min start / max end 를 추론한다.
  결과는 [EffectiveDateRange]{start, end, isDerived} 이며 저장하지 않는다.
- `lib/domain/project_filter.dart` — [ProjectFilter](all/unclassified/byId) +
  [visibleIdsForProjectFilter]. 필터에 매칭된 노드와 **그 조상 전체**를 포함해
  계층 관계가 화면에서 깨지지 않도록 한다(자식만 매칭되고 부모가 다른 project 인
  비정상 데이터에서도 부모가 맥락 표시용으로 계속 보인다).

## 12.2 VisibleTaskRow(FlatRow) 확장

`lib/ui/plan/tree_flatten.dart` 의 `FlatRow` 에 추가:
- `effectiveStartDate` / `effectiveEndDate` / `isDateDerived`
  ([computeEffectiveDateRange] 결과, flatten 시점에 1회 계산 — Tree/Gantt 양쪽이
  같은 값을 공유, 중복 계산 없음)
- `isExpanded` (= `!node.isCollapsed` 의 편의 getter)

`flattenVisibleRows(tree, {Set<String>? visibleIds})` — `visibleIds` 를 주면
그 집합에 없는 노드와 자손을 결과에서 제외한다. 생략(null)하면 기존과 완전히
동일하게 동작(하위 호환, 기존 호출부/테스트 무변경).

**중요한 판단(범위 경계)**: 기존 `GanttTimeline`/`TreePanel` 의 bar·라벨 렌더링은
여전히 `computeRollup` 기반 유효값을 그대로 쓴다(변경하지 않음). rollup 은
"autoRollup=true 면 자기 날짜가 있어도 자식 기준으로 덮어쓴다"는, 이 절의
`computeEffectiveDateRange`("자기 날짜가 있으면 무조건 우선")와 **의도적으로
다른 규칙**이라, 두 값을 뒤섞으면 이미 동작하던 rollup 기반 화면(3단계 드래그
포함)의 동작이 조용히 바뀐다. 따라서 `FlatRow` 의 새 필드는 이번 단계에서는
**추가 메타데이터로만 노출**하고(테스트로 검증됨), Today/Calendar 등 향후
화면이나, "derived parent bar 는 드래그 금지" 같은 향후 시행에 쓰도록 남겨둔다.

## 12.3 Project 필터 (Gantt 상단)

`PlanPage` 상태에 `ProjectFilter _projectFilter`(기본 `all`). AppBar 에
`_ProjectFilterSelector` 를 추가 — 옵션은 **`PlanStore.projects` 실제 데이터**로
구성(하드코딩 없음): 전체 → 실제 프로젝트들(보관됨도 필터 목록엔 노출, 이미
분류된 과거 Task 를 볼 수 있어야 하므로) → 미분류.

필터 적용 시:
- `flattenVisibleRows(tree, visibleIds: ...)` 로 트리 표시 범위를 좁힌다.
- `computeGanttMetrics(visibleNodes: ...)` 도 같은 필터링된 노드 집합으로
  계산해, 타임라인 범위가 필터 결과에 맞게 좁아진다.
- 필터 결과가 0건이면 "아직 계획된 작업이 없습니다" 빈 상태(전체 데이터가 없는
  경우와 문구/버튼을 구분) + [전체 보기로 전환]/[새 목표 추가] 제공.
- 특정 프로젝트로 필터된 상태에서 새 목표를 추가하면 그 프로젝트로 자동 배정된다
  (편집 다이얼로그에서 언제든 변경 가능).

## 12.4 status(4상태) / milestone 시각화

`lib/ui/plan/gantt_theme.dart` 에 `statusIconData`/`statusAccentColor`/
`statusBarFillColor` 추가. 색상은 기존 팔레트(primary/outline/tertiary)만
재사용(과도한 색상 추가 없음), 아이콘 모양도 상태별로 달라 색약/흑백에서도
구분 가능.

**rollup(부모 요약) 은 건드리지 않는다**: rollup 에는 4상태 집계 개념이 없으므로
(자식 중 하나가 보류여도 "요약이 보류"라는 개념 자체가 없음), leaf(또는
autoRollup=false) 노드에서만 `node.status` 를 그대로 표시하고, 요약 노드는
기존 2상태(완료/미완료) 표시를 그대로 유지한다.

**onHold != done 보장**: 색(`tertiary` vs `primary`/`outline`) + 아이콘 모양
(`pause_circle_filled` vs `check_circle`) + semantics 라벨(`kOnHoldSemantics`
= '보류' vs `kDoneSemantics` = '완료됨') 세 가지로 구분해, 색만으로 헷갈리는
경우를 방지한다.

**milestone**: `node.isMilestone==true` 면 Gantt 에서 기존 bar 로직을 타지 않고
완전히 별도 분기(`_MilestoneMarker`, 마름모)로 그린다. 기준일은 endDate 우선,
없으면 startDate, 둘 다 없으면 Gantt 에는 아무것도 그리지 않고(마커도 bar 도
없음) Tree 쪽 마일스톤 아이콘(`diamond_outlined`)만 표시한다(날짜 유무와 무관).

## 12.5 Task 편집 UI — Project/Tag 선택기

`NodeEditDialog` 가 이제 `PlanStore` 를 받는다(목록 조회 전용 — 저장은 여전히
호출자가 `PlanStore.updateNode` 로 함, 다이얼로그가 store 를 직접 변경하지 않음).

- **Project**: `DropdownButtonFormField<String?>`(null="미분류"). 보관(archived)
  프로젝트는 **새로 선택할 목록에서는 숨기되**, 현재 노드가 이미 그 프로젝트에
  속해 있으면 목록에 포함해 선택값이 사라지지 않게 한다(라벨에 "(보관됨)" 표시).
  → Gantt 상단 필터의 정책(보관 프로젝트도 필터엔 항상 노출)과는 **다른 정책**이다:
  필터는 "과거 데이터를 찾아보는 것", 편집은 "새로 배정하는 것"이라 의도적으로
  다르게 설계했다.
- **Tag**: `FilterChip` 복수 선택. **이름이 아니라 id** 를 `tagIds` 에 저장한다.

## 12.6 리스크 있었던 것 / 이미 존재했던 기능 확인

- `lib/ui/plan/gantt_timeline.dart`, `tree_panel.dart` 에는 **이미 Gantt bar
  드래그(이동/리사이즈)와 Task Tree Drag&Drop(순서 변경/계층 이동)이 구현되어
  있었다**(이전 세션에서 완료). 이번 단계는 이 기존 구현을 다시 만들지 않고,
  status/milestone 시각화만 얹었다. 드래그 관련 코드는 건드리지 않았고 회귀 테스트
  (기존 183개)로 그대로 통과 확인했다.
- `insertAt()` 이 옛 부모의 sortOrder 에 구멍을 남기는 경미한 불일치가 남아있다
  (순서 자체는 안 깨짐, `move()`/`deletePromote()` 는 이미 수정됨) — 다음
  Drag/Resize 단계에서 함께 정리 권장.

---

# 13. Drag/Resize/DnD 안정화 (신규 구현 없이 검증+보강)

## 13.1 insertAt sortOrder 불일치 — 이미 수정되어 있었음(재확인)

`plan_tree.dart` 의 `insertAt()` 을 다시 읽어보니 옛 부모 재색인 로직
(`if (oldParentId != newParentId) { _reindexSiblings(oldParentId, ...); }`)
이 **이미 존재**했다(이전 단계에서 수정 완료, 회귀 테스트도 이미 있음:
`plan_tree_test.dart` "insertAt cross-parent reindex (regression for bug #5)").
직접 probe 테스트로 재현해 확인한 결과 gap 없음을 재확인했다.

추가한 것은 **반복된 reorder/reparent 체인**(여러 번 연속 Drag 를 흉내낸) 테스트
하나뿐이다 — 매 단계마다 sortOrder 가 tight 한지 확인. 코드는 수정하지 않았다
("전체를 0,1,2,3 으로 재번호"하지 않고, 영향받는 두 parent 의 sibling 만
재색인하는 기존 정책을 그대로 유지).

## 13.2 Gantt bar 드래그 — 이미 정상 구현되어 있었음(위젯 테스트로 실증)

`gantt_timeline.dart` 의 `_GanttBar`/`_GanttBarState` 를 코드 수정 없이 그대로
검증했다. `GanttTimeline` 을 (PlanPage 없이) 직접 pump 해 정확한 픽셀 좌표로
드래그를 시뮬레이션하는 위젯 테스트를 추가했고, 다음이 실제로 보장됨을 확인:

- bar 전체 드래그 → start/end 동일 일수 이동(기간 보존)
- 좌측 핸들 → startDate 만 변경(endDate 불변)
- 우측 핸들 → endDate 만 변경(startDate 불변)
- 양방향 모두 최소 1일 clamp(start>end 방지, `resizeStart`/`resizeEnd`)
- 드래그 전체 과정에서 `PlanStore.notifyListeners` 가 **정확히 1회**만 발생
  (드래그 중 매 프레임 커밋되지 않고, 놓을 때 한 번만 커밋 — 자동저장 폭주 없음)
- Day/Week/Month 세 줌 레벨 모두에서 동일 픽셀 논리로 동일한 일수 이동 결과

### 테스트 작성 중 발견한 함정 — Flutter 제스처 slop

자동화 테스트에서 `tester.dragFrom()` 을 기본(touch) 포인터로 쓰면, 리사이즈
핸들(22px 폭) 근처에서 시작한 드래그가 **move 로 잘못 인식**되는 현상을 겪었다.
원인: Flutter 의 `HorizontalDragGestureRecognizer` 는 제스처를 "시작"으로 인정하기
전에 최소 이동거리(slop) 를 요구하고, `onDragStart` 의 `globalPosition` 은 그
**slop 을 넘긴 시점의 위치**로 보고된다. touch 포인터의 기본 slop(~수십 px) 이
핸들 폭(22px) 보다 커서, 센터 방향으로 끌면 시작 판정 시점에 이미 핸들 영역을
벗어나 move 로 오분류된다. `PointerDeviceKind.mouse` 로 시뮬레이션하면 마우스용
slop(`kPrecisePointerPanSlop`, 매우 작음) 이 적용되어 정확히 재현된다.

**이건 테스트 방법론 문제였지 프로덕션 코드의 버그가 아니다** — 실제 마우스
사용(이 앱의 1차 타깃인 PC)에서는 문제없이 동작한다. 다만 **Android(터치)에서는
잠재적으로 같은 문제가 실제로 발생할 수 있다**: 터치의 기본 slop 이 핸들
폭(22px)과 비슷하거나 크면, 사용자가 리사이즈 핸들을 정확히 터치해도 화면
중앙 쪽으로 끄는 순간 move 로 오인식될 수 있다. **이번 단계 범위(새 Drag UI
금지)를 지켜 코드를 바꾸지 않았지만, Android 실기기 검증 시 확인이 필요한
리스크로 남겨둔다** — 필요해지면 핸들 폭을 늘리거나 `kind` 인식/커스텀 slop
조정으로 해결 가능하다.

## 13.3 derived/rollup parent bar 는 드래그되지 않는다 — 이미 보장, 개념만 명확화

`_TimelineRow.build()` 에서 rollup 계산을 한 번만 하도록 정리하고, **명시적으로
이름 붙인** `canDragDate = store != null && !rollup.computedFromChildren` 를
도입했다. **동작은 바꾸지 않았다** — 기존 `_GanttBar` 의 `_canDrag`(`!isSummary`
기반) 로직을 그대로 두고, 이 새 이름은 마일스톤 드래그 게이팅에 재사용하고
정책을 문서화하는 데만 쓴다.

`effective_dates.dart` 의 `isDateDerived`(자손으로부터 추론된 표시용 값)와
`computeRollup` 의 `computedFromChildren`(autoRollup 기반 요약)은 **여전히
분리된 별개 개념**이다 — 하나로 합치지 않았다. 드래그 차단은 rollup 쪽 개념만
쓴다(그게 "지금 화면에 보이는 날짜가 사용자가 저장한 원본이 맞는가"를 뜻함).

위젯 테스트로 실증: autoRollup 부모(자식 기간에서 계산된 bar)를 드래그해도
부모/자식 어느 저장값도 바뀌지 않음을 확인.

## 13.4 milestone 드래그 — 실제로 없었던 기능을 추가(요구사항에 명시된 갭)

기존에는 `_MilestoneMarker` 가 `StatelessWidget` 으로, **드래그가 전혀
구현되어 있지 않았다**(요구사항 검토 결과 확인된 진짜 갭). "milestone 은
좌우 이동은 가능해야 하고 리사이즈는 불가능해야 한다"는 명시적 요구를 만족시키기
위해 `_MilestoneMarker` 를 `StatefulWidget` 으로 바꾸고, **기존 bar 이동에 쓰던
동일한 원시함수(`dayDeltaFromPixels`+`shiftRange`)와 동일한 커밋 정책**(드래그
중 미리보기만, 놓을 때 1회 커밋)을 그대로 재사용해 이동만 구현했다. 리사이즈
핸들 자체를 만들지 않았으므로 "리사이즈 불가"는 구조적으로 보장된다.

- 날짜가 없는 마일스톤은 마커 자체가 렌더되지 않아(`_NoDateLabel`) 애초에
  드래그할 대상이 없다.
- rollup 요약 행(위 13.3)이면 마일스톤도 동일하게 드래그를 막는다(`canDragDate`).
- `shiftRange` 가 null-safe 라 start/end 중 있는 쪽만 이동한다(마일스톤은
  둘 다 있을 수도, 하나만 있을 수도 있음).

## 13.5 Project 소속 전파 (reparent 시) — 신규 정책, 신규 코드

**이전에는 존재하지 않던 정책**이었다(확인 결과: `move()`/`insertAt()` 은
`parentId` 만 바꾸고 `projectId` 는 전혀 건드리지 않았음). 요구사항대로 다음을
구현:

    이동한 Task 의 projectId = 새 parent.projectId
    그 Task 의 모든 descendants 도 같은 projectId 로 갱신
    parent 의 projectId == null 이면 descendants 도 null

**하나의 helper**(`PlanTree.cascadeProjectId(nodeId, projectId)`)로만 처리하고,
`PlanStore.moveNode`/`reorderSibling` 두 곳(트리 변경이 일어나는 유일한 두
경로)에서 **부모가 실제로 바뀐 경우에만** 호출한다. 같은 부모 내 순서만 바꾸는
호출(reorder)은 영향받지 않는다. UI(`tree_panel.dart` 의 드래그 핸들러 등)는
`projectId` 를 직접 건드리지 않는다 — 여전히 `moveNode`/`reorderSibling` 만
호출한다.

## 13.6 Tree DnD 무결성 — 기존 보장 재확인 + 신규 케이스 테스트

순환 방지(자기 자신/자손 아래 이동 금지)는 `wouldCreateCycle`/`isDescendant`
로 이미 보장되어 있었다(기존 테스트 존재). 이번에 추가한 것:

- 필터가 활성화된 상태에서도 ID 기반 이동은 트리 전체 기준으로 정확함
  (화면에 안 보이는 노드 아래로도 정확히 이동되고, 이동 후 필터를 다시 계산해도
  계층이 깨지지 않음)
- 접힌 parent 주변에서의 이동도 정상 ordering(접힘은 순수 UI 표시 플래그이며
  트리 조작에는 전혀 영향을 주지 않음을 재확인)
- 여러 번 반복된 reorder/reparent 체인 후에도 양쪽 parent 의 sortOrder 가
  항상 tight
- Project 전파(13.5)와 결합된 reparent 시나리오
- 여러 mutation(추가+이동+projectId 전파) 후 flush → 새 PlanStore 로 reload
  했을 때 완전히 동일한 결과가 복원되는지

## 13.7 이번 단계에서 하지 않은 것

- 새로운 Drag UI, 새로운 Gantt 구조, 고급 Filter, Today, Calendar, 자동
  작업량 분배 — 요구사항대로 손대지 않았다.
- Gantt bar 이동/리사이즈, Task Tree DnD, insertAt 재색인 — 이미 정상
  동작함을 확인했으므로 **코드를 재작성하지 않고 테스트만 추가**했다.
- `effective_dates.dart` 의 `isDateDerived` 를 실제 렌더링에 연결하는 작업
  (여전히 별도 메타데이터로만 존재) — rollup 기반 렌더링을 조용히 바꾸지
  않기 위해 의도적으로 보류.
