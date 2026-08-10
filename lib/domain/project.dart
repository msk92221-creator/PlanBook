/// 최상위 분류로서의 프로젝트.
///
/// **중요**: [Project] 는 "목표(Goal)"가 아니다. 목표/서브목표/실행 작업은 모두
/// [PlanNode] 계층(parentId)으로 표현되고, [Project] 는 그 트리들을 담는
/// 최상위 분류다. 예) Project(업무) > Task(Complex Filter 완성) > Task(알고리즘 구현) ...
///
/// [PlanNode.projectId] 가 이 클래스의 [id] 를 가리킨다.
/// (parentId = 계층 / projectId = 소속·필터·집계)
library;

import 'package:flutter/foundation.dart';

@immutable
class Project {
  /// 영구 unique ID (uuid v4).
  final String id;

  /// 표시 이름. 예) 업무, 연구, 건강, 개인, 기타
  final String name;

  /// 표시 색상(ARGB 정수).
  final int color;

  /// 목록에서의 순서.
  final double sortOrder;

  /// 보관 여부. true 면 기본 목록에서 숨긴다(삭제와는 다르다).
  final bool isArchived;

  const Project({
    required this.id,
    required this.name,
    this.color = 0xFF6750A4,
    this.sortOrder = 0.0,
    this.isArchived = false,
  });

  Project copyWith({
    String? id,
    String? name,
    int? color,
    double? sortOrder,
    bool? isArchived,
  }) =>
      Project(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
        sortOrder: sortOrder ?? this.sortOrder,
        isArchived: isArchived ?? this.isArchived,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'sortOrder': sortOrder,
        'isArchived': isArchived,
      };

  /// 알려진 필드만 파싱하고 알 수 없는 필드는 무시한다.
  factory Project.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('Project requires non-empty "id"');
    }
    final rawColor = json['color'];
    final rawOrder = json['sortOrder'];
    return Project(
      id: id,
      name: json['name']?.toString() ?? '',
      color: rawColor is num
          ? rawColor.toInt()
          : int.tryParse(rawColor?.toString() ?? '') ?? 0xFF6750A4,
      sortOrder: rawOrder is num
          ? rawOrder.toDouble()
          : double.tryParse(rawOrder?.toString() ?? '') ?? 0.0,
      isArchived: json['isArchived'] == true,
    );
  }

  @override
  String toString() => 'Project($name)';

  @override
  bool operator ==(Object other) =>
      other is Project &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.sortOrder == sortOrder &&
      other.isArchived == isArchived;

  @override
  int get hashCode => Object.hash(id, name, color, sortOrder, isArchived);
}

/// 최초 실행 시 1회만 시드하는 기본 프로젝트 이름들.
/// (사용자가 지운 뒤에는 다시 생성되지 않는다 — AppSettings.seededDefaultProjects)
const List<String> kDefaultProjectNames = <String>[
  '업무',
  '연구',
  '건강',
  '개인',
  '기타',
];

/// 기본 프로젝트별 색상. [kDefaultProjectNames] 와 같은 순서.
const List<int> kDefaultProjectColors = <int>[
  0xFF3F6DE0, // 업무
  0xFF00897B, // 연구
  0xFFE0663F, // 건강
  0xFF8E5BD0, // 개인
  0xFF6B7280, // 기타
];
