/// 앱이 쓰는 로컬 디렉터리.
///
/// 데이터 파일(plan_store.json)과 기기 로컬 상태(sync_state.json 등)가 모두
/// 여기 들어간다. OneDrive 동기화는 이 폴더를 옮기는 방식이 아니라
/// Graph API 로 앱 전용 폴더와 주고받는 방식이라, 저장 위치는 항상 고정이다.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// `<appSupport>/PlanBook`.
Future<Directory> defaultLocalDir() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}${Platform.pathSeparator}PlanBook');
}
