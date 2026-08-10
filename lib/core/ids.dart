/// 안정적인 unique ID 생성 유틸.
///
/// PlanNode 의 id 는 uuid v4 문자열이며, 한번 할당되면 절대 재생성/재할당하지 않는다.
/// ID 생성 지점이 이 파일 하나에 모여 있어, 나중에 생성 전략을 바꾸기 쉽다.
library;

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// 새 unique ID(v4)를 생성한다.
String newId() => _uuid.v4();
