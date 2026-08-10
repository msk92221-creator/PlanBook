import 'package:flutter/material.dart';

import '../../core/date/plan_date.dart';
import '../../data/plan_store.dart';
import '../../domain/plan_node.dart';
import '../../domain/plan_query.dart';
import '../../domain/plan_rollup.dart';
import '../../domain/plan_tree.dart';

/// 1단계용 최소 디버그 화면.
///
/// 보여주는 것:
/// - 로드/저장 상태
/// - 트리 전체를 들여쓰기 텍스트로 출력
/// - "샘플 계획 만들기" 버튼 → 데모 데이터 생성/저장
/// - "오늘 leaf 작업" 목록(일간 뷰의 데이터 소스를 단순 리스트로 미리보기)
/// - "전체 삭제" 버튼
///
/// Gantt/드래그/필터/일간 뷰 위젯은 아직 없다(정상).
class PlanDebugScreen extends StatefulWidget {
  final PlanStore store;

  const PlanDebugScreen({super.key, required this.store});

  @override
  State<PlanDebugScreen> createState() => _PlanDebugScreenState();
}

class _PlanDebugScreenState extends State<PlanDebugScreen> {
  PlanStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    if (!_store.isLoaded) {
      _store.load();
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _onSample() async {
    _store.createSampleData();
    await _store.flush();
  }

  Future<void> _onClear() async {
    _store.clear();
    await _store.flush();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PlanBook')),
      body: _store.isLoaded
          ? _body()
          : const Center(child: CircularProgressIndicator()),
      floatingActionButton: Wrap(
        spacing: 8,
        children: [
          FloatingActionButton.extended(
            heroTag: 'sample',
            onPressed: _onSample,
            icon: const Icon(Icons.auto_mode),
            label: const Text('샘플 계획 만들기'),
          ),
          FloatingActionButton.extended(
            heroTag: 'clear',
            onPressed: _onClear,
            icon: const Icon(Icons.delete_sweep),
            label: const Text('전체 삭제'),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final tree = _store.tree;
    final today = _store.today;
    final todayLeaves = tasksCoveringDate(tree, today, leafOnly: true);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        _infoCard(today),
        const SizedBox(height: 8),
        _sectionTitle('오늘($today) leaf 작업 (${todayLeaves.length})'),
        ...todayLeaves.map((n) => _todayLeafTile(n, tree)),
        const SizedBox(height: 12),
        _sectionTitle('전체 트리 (${tree.length})'),
        ..._renderTree(tree),
      ],
    );
  }

  Widget _infoCard(PlanDate today) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'PlanBook 1단계 디버그 화면\n'
          '오늘: $today\n'
          '저장소: JSON 원자적 쓰기 / autosave + flush\n'
          '이 화면은 최소 확인용. Gantt/드래그/필터/일간 뷰는 2~4단계.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _todayLeafTile(PlanNode node, PlanTree tree) {
    final r = computeRollup(tree, node.id);
    return ListTile(
      dense: true,
      leading: Icon(
        node.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 20,
      ),
      title: Text(node.title),
      subtitle: Text(
        '${node.startDate ?? '?'} ~ ${node.endDate ?? '?'}  '
        'p=${(r.progress * 100).round()}%  [${node.projectId ?? '-'}]',
      ),
    );
  }

  List<Widget> _renderTree(PlanTree tree) {
    final lines = <Widget>[];
    void visit(String? parentId, int depth) {
      for (final n in tree.childrenOf(parentId)) {
        lines.add(_treeTile(n, depth, tree));
        visit(n.id, depth + 1);
      }
    }

    visit(null, 0);
    if (lines.isEmpty) {
      lines.add(const Padding(
        padding: EdgeInsets.all(16),
        child: Text('데이터 없음. "샘플 계획 만들기"를 눌러 보세요.'),
      ));
    }
    return lines;
  }

  Widget _treeTile(PlanNode node, int depth, PlanTree tree) {
    final r = computeRollup(tree, node.id);
    final indent = '  ' * depth;
    final period =
        '${node.startDate?.toIso() ?? '?'}~${node.endDate?.toIso() ?? '?'}';
    final eff =
        '${r.startDate?.toIso() ?? '?'}~${r.endDate?.toIso() ?? '?'} '
        'p=${(r.progress * 100).round()}% done=${r.isDone}'
        '${r.computedFromChildren ? '(rollup)' : ''}';
    return Padding(
      padding: EdgeInsets.only(left: 8.0 + depth * 12.0, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$indent• ${node.title}  '
            '[${node.priority.label}${node.nodeKind.name != 'project' ? '/${node.nodeKind.label}' : ''}]',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            '$indent  저장: $period   유효: $eff',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
