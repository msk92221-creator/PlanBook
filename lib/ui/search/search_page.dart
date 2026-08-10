/// 검색 화면 — 제목/메모/프로젝트 이름/태그 이름을 대상으로 실시간 검색한다.
///
/// 별도 검색 인덱스를 만들지 않는다. 매 입력마다 [searchNodes] 로 현재
/// [PlanStore] 트리를 그대로 다시 스캔한다(개인용 데이터 규모를 가정한
/// 단순 구현 — Calendar/Filter 와 동일한 설계 원칙).
library;

import 'package:flutter/material.dart';

import '../../data/plan_store.dart';
import '../../domain/plan_node.dart';
import '../../domain/search_query.dart';
import '../common/navigation.dart';
import '../common/task_row.dart';
import '../plan/node_edit_dialog.dart';

class SearchPage extends StatefulWidget {
  final PlanStore store;
  final OpenInGantt? onOpenInGantt;

  const SearchPage({super.key, required this.store, this.onOpenInGantt});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  PlanStore get _store => widget.store;
  final _queryCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    if (!_store.isLoaded) _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String? _projectName(String? id) => _store.projectById(id)?.name;
  String _tagName(String id) => _store.tagById(id)?.name ?? '';

  List<String> _breadcrumb(PlanNode node) {
    final out = <String>[];
    final project = _store.projectById(node.projectId);
    if (project != null) out.add(project.name);
    out.addAll(_store.tree.ancestorsOf(node.id).reversed.map((a) => a.title));
    return out;
  }

  Future<void> _editNode(PlanNode node) async {
    final result = await showNodeEditDialog(
      context,
      tree: _store.tree,
      node: node,
      store: _store,
    );
    if (result == null) return;
    commitNodeEdit(_store, node, result);
  }

  @override
  Widget build(BuildContext context) {
    if (!_store.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final results = searchNodes(
      _store.tree,
      _query,
      projectName: _projectName,
      tagName: _tagName,
      today: _store.today,
    );

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _queryCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '제목, 메모, 프로젝트, 태그 검색',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '지우기',
              onPressed: () => setState(() {
                _queryCtrl.clear();
                _query = '';
              }),
            ),
        ],
      ),
      body: _query.trim().isEmpty
          ? const Center(child: Text('검색어를 입력하세요.'))
          : results.isEmpty
              ? const Center(child: Text('검색 결과가 없습니다.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('결과 ${results.length}건',
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    for (final n in results)
                      TaskRow(
                        node: n,
                        breadcrumb: _breadcrumb(n),
                        onToggleDone: () => _store.setNodeDone(n.id, !n.isDone),
                        onTap: () => _editNode(n),
                        onOpenInGantt: widget.onOpenInGantt == null
                            ? null
                            : () => widget.onOpenInGantt!(focusNodeId: n.id),
                      ),
                  ],
                ),
    );
  }
}
