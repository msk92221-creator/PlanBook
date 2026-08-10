/// 작업에 붙이는 자유 라벨.
///
/// [PlanNode.tagIds] 가 이 클래스의 [id] 목록을 가리킨다.
/// (이름이 아니라 id 로 참조하므로 태그 이름을 바꿔도 연결이 끊기지 않는다)
library;

import 'package:flutter/foundation.dart';

@immutable
class Tag {
  /// 영구 unique ID (uuid v4).
  final String id;

  /// 표시 이름.
  final String name;

  /// 표시 색상(ARGB 정수).
  final int color;

  const Tag({
    required this.id,
    required this.name,
    this.color = 0xFF6B7280,
  });

  Tag copyWith({String? id, String? name, int? color}) => Tag(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'color': color,
      };

  /// 알려진 필드만 파싱하고 알 수 없는 필드는 무시한다.
  factory Tag.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('Tag requires non-empty "id"');
    }
    final rawColor = json['color'];
    return Tag(
      id: id,
      name: json['name']?.toString() ?? '',
      color: rawColor is num
          ? rawColor.toInt()
          : int.tryParse(rawColor?.toString() ?? '') ?? 0xFF6B7280,
    );
  }

  @override
  String toString() => 'Tag($name)';

  @override
  bool operator ==(Object other) =>
      other is Tag &&
      other.id == id &&
      other.name == name &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, name, color);
}
