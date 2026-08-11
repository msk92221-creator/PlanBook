/// OneDrive(로컬 폴더) 동기화 설정.
///
/// **동기화 방식**: 별도의 클라우드 API 연동 없이, 앱의 데이터 파일
/// (plan_store.json)을 사용자가 지정한 로컬 폴더(보통 OneDrive 동기화 폴더
/// 안)에 그대로 저장한다. 여러 기기 간 실제 동기화는 OneDrive 클라이언트가
/// 그 폴더를 감시하며 처리하고, 앱은 "저장 위치를 어디로 할지"만 책임진다.
/// [JsonPlanRepository]가 이미 임의의 [Directory]를 저장 위치로 받으므로,
/// 새 저장 백엔드를 만들 필요 없이 그 디렉터리를 동기화 폴더로 바꿔 끼우면
/// 된다.
///
/// 이 설정(동기화 폴더 경로)은 기기마다 다를 수 있으므로(OneDrive 마운트
/// 경로가 기기별로 다름) **동기화되는 데이터 파일(plan_store.json) 안에는
/// 넣지 않는다** — 항상 로컬 전용 위치([defaultLocalDir])에 별도 파일로 둔다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const String _kSyncConfigFileName = 'sync_config.json';

/// 동기화 설정. [folderPath]가 null/빈 문자열이면 동기화 꺼짐(기기 로컬 저장).
@immutable
class SyncConfig {
  final String? folderPath;

  const SyncConfig({this.folderPath});

  bool get isEnabled => folderPath != null && folderPath!.isNotEmpty;

  Map<String, Object?> toJson() => {'folderPath': folderPath};

  factory SyncConfig.fromJson(Map<String, Object?> json) =>
      SyncConfig(folderPath: json['folderPath']?.toString());

  @override
  bool operator ==(Object other) =>
      other is SyncConfig && other.folderPath == folderPath;

  @override
  int get hashCode => folderPath.hashCode;
}

/// 앱의 기본 로컬 저장 디렉터리(`<appSupport>/PlanBook`). 동기화 켜짐/꺼짐과
/// 무관하게 **동기화 설정 파일 자체는 항상 여기 있다** — 동기화 대상 폴더가
/// 무엇인지 알아야 할 다음 실행이, 그 정보를 알아내려고 동기화 폴더부터
/// 먼저 읽는 순환에 빠지지 않게 하기 위해서다.
Future<Directory> defaultLocalDir() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}${Platform.pathSeparator}PlanBook');
}

File _configFile(Directory localDir) =>
    File('${localDir.path}${Platform.pathSeparator}$_kSyncConfigFileName');

/// [localDir]에서 동기화 설정을 읽는다. 파일이 없거나 손상된 경우 빈 설정
/// (동기화 꺼짐)을 반환한다(예외 없음 — 다른 저장소 코드와 동일한 정책).
Future<SyncConfig> loadSyncConfig(Directory localDir) async {
  try {
    final file = _configFile(localDir);
    if (!await file.exists()) return const SyncConfig();
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return const SyncConfig();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return const SyncConfig();
    return SyncConfig.fromJson(decoded);
  } catch (_) {
    return const SyncConfig();
  }
}

/// [config]를 [localDir]에 저장한다(항상 로컬 전용 위치, 덮어쓰기).
Future<void> saveSyncConfig(Directory localDir, SyncConfig config) async {
  if (!await localDir.exists()) {
    await localDir.create(recursive: true);
  }
  await _configFile(localDir).writeAsString(jsonEncode(config.toJson()));
}

/// 사용자가 고른 원드라이브(등) 폴더 경로 아래 실제 데이터가 저장될 하위
/// 폴더. 사용자가 고른 폴더 바로 아래에 `plan_store.json`을 흩뿌리지 않고,
/// 로컬 기본 저장 위치와 동일하게 `PlanBook` 하위 폴더를 둔다.
Directory syncDataDir(String pickedFolderPath) =>
    Directory('$pickedFolderPath${Platform.pathSeparator}PlanBook');

/// [config]를 반영해 실제 데이터 저장 디렉터리를 고른다. 동기화가 꺼져
/// 있으면 [localDir], 켜져 있으면 [syncDataDir]이 가리키는 폴더.
Directory resolveDataDir(Directory localDir, SyncConfig config) {
  if (!config.isEnabled) return localDir;
  return syncDataDir(config.folderPath!);
}
