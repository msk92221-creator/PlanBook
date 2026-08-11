/// 프로젝트 계획 페이지(Gantt 메인 화면).
///
/// 좌측 트리 + 우측 Gantt 타임라인 2분할. 좁은 화면에서는 트리/타임라인 전환.
/// - 행 높이/순서 정렬: [flattenVisibleRows] 결과를 양쪽 패널에 공유.
/// - 세로 스크롤 동기화: 좌/우 패널 컨트롤러를 리스너로 묶음.
/// - 가로 스크롤: 우측 타임라인. 트랙패드/터치/스크롤바 자연 지원.
/// - 일/주/월 줌.
/// - "오늘" 은 store.today 에서 주입(위젯이 DateTime.now() 직접 호출 금지).
/// - 빈 상태에서 샘플 계획 생성 가능.
/// - 고급 필터([PlanFilterState]) — 판정은 domain/plan_filter.dart 순수 함수.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import '../../core/date/plan_date.dart';
import '../../data/plan_store.dart';
import '../../domain/plan_filter.dart';
import '../../domain/plan_node.dart';
import '../filter/filter_bar.dart';
import 'gantt_metrics.dart';
import 'gantt_theme.dart';
import 'gantt_timeline.dart';
import 'node_edit_dialog.dart';
import 'tree_flatten.dart';
import 'tree_panel.dart';

class PlanPage extends StatefulWidget {
  final PlanStore store;

  /// Gantt 진입 시 미리 적용할 필터(예: Projects 화면에서 "이 프로젝트 보기").
  /// null 이면 이전 상태(또는 빈 필터)를 그대로 쓴다.
  final PlanFilterState? initialFilter;

  /// Gantt 에서 특정 Task 로 스크롤/강조 이동하고 싶을 때 쓰는 대상 id
  /// (Today/Calendar/검색에서 넘어올 때 사용).
  final String? focusNodeId;

  const PlanPage({
    super.key,
    required this.store,
    this.initialFilter,
    this.focusNodeId,
  });

  @override
  State<PlanPage> createState() => _PlanPageState();
}

enum _NarrowView { tree, timeline }

class _PlanPageState extends State<PlanPage> {
  PlanStore get _store => widget.store;

  GanttZoomLevel _zoom = GanttZoomLevel.week;
  _NarrowView _narrowView = _NarrowView.tree;

  /// 상단 고급 필터. 화면 상태로만 유지한다(AppShell 이 IndexedStack 으로
  /// 화면을 보존하므로 탭을 오가도 값이 살아있다. 별도 저장은 하지 않는다).
  PlanFilterState _filter = PlanFilterState.empty;

  /// 현재 강조(선택) 표시 중인 Task id.
  String? _selectedNodeId;

  // 좌/우 세로 스크롤 동기화.
  final ScrollController _leftV = ScrollController();
  final ScrollController _rightV = ScrollController();
  bool _syncing = false;

  // 타임라인 가로 스크롤.
  final ScrollController _hCtrl = ScrollController();
  bool _didInitialTodayScroll = false;
  GanttZoomLevel? _lastZoomForScroll;
  // 창 크기 변경 시 "오늘" 위치 재보정을 위해 이전 폭 기억.
  double? _lastViewWidth;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter != null) _filter = widget.initialFilter!;
    _selectedNodeId = widget.focusNodeId;
    _store.addListener(_onChanged);
    if (!_store.isLoaded) {
      _store.load();
    }
    _leftV.addListener(_syncFromLeft);
    _rightV.addListener(_syncFromRight);
  }

  @override
  void didUpdateWidget(PlanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Projects 화면 등에서 다시 진입하며 새 initialFilter/focusNodeId 를 주면 반영.
    if (widget.initialFilter != null &&
        widget.initialFilter != oldWidget.initialFilter) {
      setState(() => _filter = widget.initialFilter!);
    }
    if (widget.focusNodeId != null &&
        widget.focusNodeId != oldWidget.focusNodeId) {
      setState(() {
        _selectedNodeId = widget.focusNodeId;
        _didInitialTodayScroll = false; // 포커스 대상으로 다시 스크롤 유도.
      });
    }
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    _leftV.removeListener(_syncFromLeft);
    _rightV.removeListener(_syncFromRight);
    _leftV.dispose();
    _rightV.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _syncFromLeft() {
    if (_syncing || !_leftV.hasClients) return;
    _syncing = true;
    if (_rightV.hasClients) {
      _rightV.jumpTo(_leftV.offset);
    }
    _syncing = false;
  }

  void _syncFromRight() {
    if (_syncing || !_rightV.hasClients) return;
    _syncing = true;
    if (_leftV.hasClients) {
      _leftV.jumpTo(_rightV.offset);
    }
    _syncing = false;
  }

  void _toggleCollapse(PlanNode node) {
    _store.updateNode(
      node.id,
      (n) => n.copyWith(isCollapsed: !n.isCollapsed),
    );
  }

  Future<void> _onSample() async {
    _store.createSampleData();
    await _store.flush();
  }

  Future<void> _onClear() async {
    _store.clear();
    await _store.flush();
  }

  Future<void> _onAddRoot() async {
    // 필터에 프로젝트가 정확히 하나만 선택돼 있으면 새 목표를 그 프로젝트에 바로
    // 소속시킨다(편집 다이얼로그에서 언제든 바꿀 수 있음). 0개/여러 개면 미분류.
    final seedProjectId =
        _filter.projectIds.length == 1 ? _filter.projectIds.first : null;
    final node =
        _store.addNode(parentId: null, title: '', projectId: seedProjectId);
    if (!mounted) return;
    // tree_panel 의 동일 흐름을 재사용: 편집 다이얼로그로 제목 입력, 취소 시 제거.
    final result = await showNodeEditDialog(
      context,
      tree: _store.tree,
      node: node,
      store: _store,
    );
    if (result == null) {
      if (_store.tree.contains(node.id)) {
        _store.deleteCascade(node.id);
      }
      return;
    }
    commitNodeEdit(_store, node, result);
  }

  /// 현재 [_filter] 를 적용한 결과(매칭 + 맥락 조상). 빈 필터면 전체.
  FilterVisibility get _visibility => computeFilterVisibility(
        _store.tree,
        _filter,
        today: _store.today,
        weekStartWeekday: _store.settings.weekStart,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PlanBook'),
        actions: [
          _ZoomSelector(
            value: _zoom,
            onChanged: (z) => setState(() {
              _zoom = z;
              _didInitialTodayScroll = false;
              _lastZoomForScroll = null;
            }),
          ),
          IconButton(
            tooltip: '오늘로 이동',
            onPressed: () => setState(() {
              _selectedNodeId = null;
              _didInitialTodayScroll = false;
            }),
            icon: const Icon(Icons.today_outlined),
          ),
          IconButton(
            tooltip: '실행 취소(Ctrl+Z)',
            onPressed: _store.canUndo ? () => _store.undo() : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: '다시 실행(Ctrl+Y)',
            onPressed: _store.canRedo ? () => _store.redo() : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: '최상위 목표 추가',
            onPressed: _onAddRoot,
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: '전체 삭제',
            onPressed: _store.isEmpty ? null : _onClear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: _store.isLoaded ? _body() : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _body() {
    if (_store.isEmpty) {
      return _emptyState(filtered: false);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kTwoPaneBreakpoint;
        final visibility = _visibility;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: FilterBar(
                store: _store,
                value: _filter,
                compact: !wide,
                onChanged: (f) => setState(() => _filter = f),
              ),
            ),
            Expanded(
              child: visibility.visibleIds.isEmpty
                  ? _emptyState(filtered: true)
                  : Listener(
                      onPointerSignal: _onPointerSignal,
                      child: wide
                          ? _twoPane(context, visibility)
                          : _narrowPane(context, visibility),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _twoPane(BuildContext context, FilterVisibility visibility) {
    final rows = flattenVisibleRows(
      _store.tree,
      // 필터가 비어있으면 visibleIds=null 로 넘겨야 한다 — flattenVisibleRows 는
      // visibleIds!=null 이면 "필터 중" 으로 보고 접힌 노드도 강제로 펼치는데,
      // 필터가 없을 땐 그러면 안 되고 접기 상태를 원래대로 존중해야 한다.
      visibleIds: _filter.isEmpty ? null : visibility.visibleIds,
      matchedIds: _filter.isEmpty ? null : visibility.matchedIds,
      contextAncestorIds: _filter.isEmpty ? null : visibility.contextAncestorIds,
    );
    final metrics = computeGanttMetrics(
      visibleNodes:
          _store.tree.allNodes.where((n) => visibility.visibleIds.contains(n.id)),
      zoom: _zoom,
      today: _store.today,
    );
    _scheduleInitialScroll(metrics, rows);

    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: kTreePaneWidth,
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: scheme.outlineVariant, width: 1),
                  ),
                ),
                child: TreePanel(
                  tree: _store.tree,
                  rows: rows,
                  verticalController: _leftV,
                  onToggleCollapse: _toggleCollapse,
                  store: _store,
                  selectedNodeId: _selectedNodeId,
                  onSelect: (id) => setState(() => _selectedNodeId = id),
                ),
              ),
              Expanded(
                child: GanttTimeline(
                  tree: _store.tree,
                  rows: rows,
                  metrics: metrics,
                  today: _store.today,
                  verticalController: _rightV,
                  horizontalController: _hCtrl,
                  store: _store,
                  selectedNodeId: _selectedNodeId,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _narrowPane(BuildContext context, FilterVisibility visibility) {
    final rows = flattenVisibleRows(
      _store.tree,
      visibleIds: _filter.isEmpty ? null : visibility.visibleIds,
      matchedIds: _filter.isEmpty ? null : visibility.matchedIds,
      contextAncestorIds: _filter.isEmpty ? null : visibility.contextAncestorIds,
    );
    final metrics = computeGanttMetrics(
      visibleNodes:
          _store.tree.allNodes.where((n) => visibility.visibleIds.contains(n.id)),
      zoom: _zoom,
      today: _store.today,
    );
    _scheduleInitialScroll(metrics, rows);

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SegmentedButton<_NarrowView>(
              segments: const [
                ButtonSegment(
                  value: _NarrowView.tree,
                  icon: Icon(Icons.account_tree_outlined),
                  label: Text('트리'),
                ),
                ButtonSegment(
                  value: _NarrowView.timeline,
                  icon: Icon(Icons.view_timeline_outlined),
                  label: Text('타임라인'),
                ),
              ],
              selected: {_narrowView},
              onSelectionChanged: (s) => setState(() => _narrowView = s.first),
            ),
          ),
        ),
        Expanded(
          child: _narrowView == _NarrowView.tree
              ? TreePanel(
                  tree: _store.tree,
                  rows: rows,
                  verticalController: _leftV,
                  onToggleCollapse: _toggleCollapse,
                  store: _store,
                  selectedNodeId: _selectedNodeId,
                  onSelect: (id) => setState(() => _selectedNodeId = id),
                )
              : GanttTimeline(
                  tree: _store.tree,
                  rows: rows,
                  metrics: metrics,
                  today: _store.today,
                  verticalController: _rightV,
                  horizontalController: _hCtrl,
                  store: _store,
                  selectedNodeId: _selectedNodeId,
                ),
        ),
      ],
    );
  }

  /// 가로 스크롤: 앱 처음 열었을 때(또는 "오늘로 이동"/focusNodeId 지정 시)
  /// 오늘 또는 포커스 대상이 보이도록. 창 크기가 바뀐 후에도 자연스럽게
  /// 가시권에 들어오도록 보정한다.
  void _scheduleInitialScroll(GanttMetrics metrics, List<FlatRow> rows) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_hCtrl.hasClients) return;
      final viewWidth = _hCtrl.position.viewportDimension;

      double targetX;
      final focusId = _selectedNodeId;
      PlanDate? focusStart;
      if (focusId != null) {
        for (final r in rows) {
          if (r.id == focusId) {
            focusStart = r.effectiveStartDate;
            break;
          }
        }
      }
      targetX = focusStart != null
          ? metrics.xForDate(focusStart)
          : metrics.xForToday(_store.today);

      // 폭이 바뀌었고 대상이 현재 가시영역 밖이면 다시 가시권으로.
      final needsRecenter = (_lastViewWidth != null &&
          (_lastViewWidth! - viewWidth).abs() > 1 &&
          _didInitialTodayScroll &&
          _lastZoomForScroll == _zoom);
      _lastViewWidth = viewWidth;

      if (!_didInitialTodayScroll || _lastZoomForScroll != _zoom) {
        final target = (targetX - viewWidth / 2).clamp(
          0.0,
          _hCtrl.position.maxScrollExtent,
        );
        _hCtrl.jumpTo(target);
        _didInitialTodayScroll = true;
        _lastZoomForScroll = _zoom;
        return;
      }
      if (needsRecenter) {
        final offset = _hCtrl.offset;
        final visibleEnd = offset + viewWidth;
        const margin = 60.0;
        if (targetX < offset + margin || targetX > visibleEnd - margin) {
          final target = (targetX - viewWidth / 2).clamp(
            0.0,
            _hCtrl.position.maxScrollExtent,
          );
          _hCtrl.jumpTo(target);
        }
      }
    });
  }

  /// shift + 마우스휠 → 가로 스크롤.
  /// 일반 휠(세로) 은 그대로 세로 스크롤/스크롤뷰 기본 동작에 맡긴다.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final shift = HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.shiftLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.shiftRight);
      if (shift && _hCtrl.hasClients) {
        final pos = _hCtrl.position;
        final max = pos.maxScrollExtent;
        final newOffset =
            (pos.pixels + event.scrollDelta.dx + event.scrollDelta.dy)
                .clamp(0.0, max);
        _hCtrl.jumpTo(newOffset);
      }
    }
  }

  /// [filtered]==true 면 "데이터는 있지만 현재 필터에 걸리는 게 없음" 상태.
  /// (전체 데이터가 아예 없는 [filtered]==false 상태와 문구/버튼을 구분한다)
  Widget _emptyState({required bool filtered}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered ? Icons.filter_alt_off_outlined : Icons.event_note_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              filtered ? '아직 계획된 작업이 없습니다.' : '계획이 없습니다',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              filtered
                  ? '현재 필터 조건에 해당하는 작업이 없습니다.\n필터를 바꾸거나 새 목표를 추가하세요.'
                  : '목표/서브목표/작업을 트리로 구성하고\nGantt 타임라인으로 한눈에 확인하세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            if (filtered) ...[
              FilledButton.icon(
                onPressed: _onAddRoot,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('새 목표 추가'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _filter = PlanFilterState.empty),
                child: const Text('전체 보기로 전환'),
              ),
            ] else ...[
              // "새 목표 추가" 를 기본 진입점으로 삼는다 — 샘플 생성 버튼만
              // 있으면 사용자가 자기 계획을 어떻게 시작해야 할지 알 수 없다.
              FilledButton.icon(
                onPressed: _onAddRoot,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('새 목표 추가'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _onSample,
                icon: const Icon(Icons.auto_mode),
                label: const Text('샘플 계획으로 둘러보기'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 줌 선택기
// ---------------------------------------------------------------------------

class _ZoomSelector extends StatelessWidget {
  final GanttZoomLevel value;
  final ValueChanged<GanttZoomLevel> onChanged;

  const _ZoomSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ToggleButtons(
        isSelected: GanttZoomLevel.values.map((z) => z == value).toList(),
        onPressed: (i) => onChanged(GanttZoomLevel.values[i]),
        constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
        borderRadius: BorderRadius.circular(8),
        children: [
          for (final z in GanttZoomLevel.values) Text(z.label),
        ],
      ),
    );
  }
}
