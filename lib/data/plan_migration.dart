/// 저장 파일 스키마 마이그레이션.
///
/// 저장 파일에는 `schemaVersion` 이 들어 있고, 구버전을 읽을 때 이 파일의
/// 함수가 신버전 구조로 변환한다. **저장 로직(원자적 rename, .tmp 복구)은
/// 건드리지 않는다** — 여기서는 파싱된 payload 를 변환할 뿐이다.
///
/// v1 -> v2 변환:
///   - Task.category(String)  -> 같은 이름 Project 를 찾고, 없으면 생성 -> projectId
///   - Task.tags(`List<String>`) -> 같은 이름 Tag 를 찾고, 없으면 생성 -> tagIds
///   - Task.isDone(bool)       -> TaskStatus
///        true            -> done
///        false && p > 0  -> inProgress
///        그 외            -> notStarted
///     (이 규칙 자체는 [PlanNode.parseStatus] 에 있다)
library;

import '../core/ids.dart';
import '../domain/app_settings.dart';
import '../domain/plan_node.dart';
import '../domain/project.dart';
import '../domain/tag.dart';
import 'plan_repository.dart';

/// 파싱된 최상위 JSON map 을 현재 스키마의 [PlanSnapshot] 으로 변환한다.
///
/// 알 수 없는 필드는 무시하고, 개별 항목이 깨져 있어도 그 항목만 건너뛴다
/// (전체 로드가 실패하지 않게 한다).
PlanSnapshot snapshotFromJson(Map<String, Object?> decoded) {
  final rawVersion = decoded['schemaVersion'];
  final schemaVersion = rawVersion is num
      ? rawVersion.toInt()
      : int.tryParse(rawVersion?.toString() ?? '') ??
          PlanSnapshot.currentSchemaVersion;

  final projects = <Project>[];
  final projectsRaw = decoded['projects'];
  if (projectsRaw is List) {
    for (final item in projectsRaw) {
      if (item is Map<String, Object?>) {
        try {
          projects.add(Project.fromJson(item));
        } catch (_) {
          // 깨진 항목은 건너뛴다.
        }
      }
    }
  }

  final tags = <Tag>[];
  final tagsRaw = decoded['tags'];
  if (tagsRaw is List) {
    for (final item in tagsRaw) {
      if (item is Map<String, Object?>) {
        try {
          tags.add(Tag.fromJson(item));
        } catch (_) {
          // 깨진 항목은 건너뛴다.
        }
      }
    }
  }

  final settingsRaw = decoded['settings'];
  final settings = settingsRaw is Map<String, Object?>
      ? AppSettings.fromJson(settingsRaw)
      : const AppSettings();

  // ---- 노드 파싱 + (필요 시) v1 레거시 필드 변환 ----
  //
  // 이름 -> id 조회표. 구버전의 category/tags 문자열을 id 로 연결할 때 쓰고,
  // 없으면 새 Project/Tag 를 만들어 등록한다.
  final projectIdByName = <String, String>{
    for (final p in projects) p.name: p.id,
  };
  final tagIdByName = <String, String>{
    for (final t in tags) t.name: t.id,
  };

  String projectIdFor(String name) {
    final existing = projectIdByName[name];
    if (existing != null) return existing;
    final created = Project(
      id: newId(),
      name: name,
      color: _colorForDefaultProject(name),
      sortOrder: projects.length.toDouble(),
    );
    projects.add(created);
    projectIdByName[name] = created.id;
    return created.id;
  }

  String tagIdFor(String name) {
    final existing = tagIdByName[name];
    if (existing != null) return existing;
    final created = Tag(id: newId(), name: name);
    tags.add(created);
    tagIdByName[name] = created.id;
    return created.id;
  }

  final nodes = <PlanNode>[];
  final nodesRaw = decoded['nodes'];
  if (nodesRaw is List) {
    for (final item in nodesRaw) {
      if (item is! Map<String, Object?>) continue;
      try {
        var node = PlanNode.fromJson(item);

        // v1 레거시: category 문자열 -> Project 로 승격.
        if (node.projectId == null) {
          final legacyCategory = item['category']?.toString();
          if (legacyCategory != null && legacyCategory.isNotEmpty) {
            node = node.copyWith(projectId: projectIdFor(legacyCategory));
          }
        }

        // v1 레거시: tags 문자열 배열 -> Tag 로 승격.
        if (node.tagIds.isEmpty) {
          final legacyTags = item['tags'];
          if (legacyTags is List && legacyTags.isNotEmpty) {
            final ids = <String>[];
            for (final t in legacyTags) {
              final name = t.toString();
              if (name.isEmpty) continue;
              ids.add(tagIdFor(name));
            }
            if (ids.isNotEmpty) {
              node = node.copyWith(tagIds: List<String>.unmodifiable(ids));
            }
          }
        }

        nodes.add(node);
      } catch (_) {
        // 깨진 노드는 건너뛴다(전체 로드를 죽이지 않는다).
      }
    }
  }

  return PlanSnapshot(
    // 읽어들인 뒤에는 항상 현재 스키마로 취급한다(다음 저장 때 v2 로 기록된다).
    schemaVersion: schemaVersion < PlanSnapshot.currentSchemaVersion
        ? PlanSnapshot.currentSchemaVersion
        : schemaVersion,
    nodes: nodes,
    projects: projects,
    tags: tags,
    settings: settings,
  );
}

/// [PlanSnapshot] 을 저장용 JSON map 으로.
Map<String, Object?> snapshotToJson(PlanSnapshot snapshot) => {
      'schemaVersion': snapshot.schemaVersion,
      'nodes': snapshot.nodes.map((n) => n.toJson()).toList(),
      'projects': snapshot.projects.map((p) => p.toJson()).toList(),
      'tags': snapshot.tags.map((t) => t.toJson()).toList(),
      'settings': snapshot.settings.toJson(),
    };

/// 기본 프로젝트 이름이면 정해진 색, 아니면 기본색.
int _colorForDefaultProject(String name) {
  final i = kDefaultProjectNames.indexOf(name);
  return i >= 0 ? kDefaultProjectColors[i] : 0xFF6750A4;
}
