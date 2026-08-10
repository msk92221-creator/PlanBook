/// 영속화 계층의 추상 인터페이스와 스냅샷 모델.
///
/// 저장 방식(JSON 파일)은 구현체([JsonPlanRepository]) 뒤에 숨긴다.
/// 나중에 sqflite/기타 백엔드로 교체할 때 이 인터페이스만 구현하면 된다.
///
/// **모든 데이터는 이 하나의 스냅샷에 담겨 하나의 파일로 저장된다.**
/// 엔티티가 늘었다고 별도 파일/별도 저장 경로를 만들지 않는다.
library;

import '../domain/app_settings.dart';
import '../domain/plan_node.dart';
import '../domain/project.dart';
import '../domain/tag.dart';

/// 저장 파일의 최상위 구조.
class PlanSnapshot {
  /// 파일 포맷 버전. 향후 마이그레이션 기준.
  ///
  /// - v1: nodes 만. Task 에 category(String)/tags(`List<String>`)/isDone(bool).
  /// - v2: projects/tags/settings 추가. Task 는 projectId/tagIds/status/isMilestone.
  static const int currentSchemaVersion = 2;

  final int schemaVersion;

  /// flat 한 노드 리스트. parentId/sortOrder 로 트리 복원 가능.
  final List<PlanNode> nodes;

  /// 최상위 분류 목록.
  final List<Project> projects;

  /// 태그 목록.
  final List<Tag> tags;

  /// 앱 설정.
  final AppSettings settings;

  const PlanSnapshot({
    required this.schemaVersion,
    required this.nodes,
    this.projects = const [],
    this.tags = const [],
    this.settings = const AppSettings(),
  });

  /// 빈 초기 상태.
  factory PlanSnapshot.empty() =>
      PlanSnapshot(schemaVersion: currentSchemaVersion, nodes: const []);
}

/// 영속화 인터페이스.
///
/// - [load] 는 파일이 없거나 손상된 경우 예외를 던지지 **않**고 빈 상태(null)을
///   반환하도록 구현해야 한다(앱 크래시 방지).
/// - [save] 는 원자적 쓰기(임시 파일 → rename)로 구현해야 한다.
abstract class PlanRepository {
  Future<PlanSnapshot?> load();

  Future<void> save(PlanSnapshot snapshot);
}
