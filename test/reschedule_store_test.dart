import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/reschedule.dart';

class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

Future<PlanStore> _storeOn(DateTime date) async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => date,
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  return store;
}

void main() {
  group('PlanStore.rescheduleNode', () {
    test('사용자가 "오늘로 이동" 을 선택하면 실제로 날짜가 바뀐다', () async {
      final store = await _storeOn(DateTime(2026, 8, 11));
      final node = store.addNode(
        title: '밀린 작업',
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 5),
      );
      await store.flush();

      final changed =
          store.rescheduleNode(node.id, RescheduleOption.today);
      expect(changed, isTrue);
      final updated = store.tree[node.id]!;
      expect(updated.endDate, PlanDate(2026, 8, 11));
      await store.flush();
      store.dispose();
    });

    test('keepAsIs 는 아무것도 바꾸지 않고 false 를 반환한다', () async {
      final store = await _storeOn(DateTime(2026, 8, 11));
      final node = store.addNode(
        title: '밀린 작업',
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 5),
      );
      await store.flush();

      final changed =
          store.rescheduleNode(node.id, RescheduleOption.keepAsIs);
      expect(changed, isFalse);
      expect(store.tree[node.id]!.endDate, PlanDate(2026, 8, 5));
      store.dispose();
    });

    test('존재하지 않는 id 는 false', () async {
      final store = await _storeOn(DateTime(2026, 8, 11));
      expect(store.rescheduleNode('없음', RescheduleOption.today), isFalse);
      store.dispose();
    });

    test('specificDate 옵션은 지정한 날짜로 이동한다', () async {
      final store = await _storeOn(DateTime(2026, 8, 11));
      final node = store.addNode(
        title: '밀린 작업',
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 5),
      );
      await store.flush();

      store.rescheduleNode(node.id, RescheduleOption.specificDate,
          specificDate: PlanDate(2026, 9, 1));
      expect(store.tree[node.id]!.endDate, PlanDate(2026, 9, 1));
      await store.flush();
      store.dispose();
    });
  });
}
