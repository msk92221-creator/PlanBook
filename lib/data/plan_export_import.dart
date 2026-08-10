/// 내보내기/가져오기(서버리스 백업).
///
/// **기존 저장 포맷을 그대로 재사용한다** — [PlanSnapshot]/[snapshotToJson]/
/// [snapshotFromJson](plan_migration.dart) 을 그대로 쓰고, 백업 전용 포맷을
/// 새로 만들지 않는다. 따라서 백업 파일은 `plan_store.json` 과 완전히 같은
/// 구조이고, schemaVersion 체크·마이그레이션·손상 항목 스킵도 그대로 적용된다.
///
/// 이번 라운드는 OneDrive API 연동을 하지 않는다(요구사항). 대신 앱 문서
/// 폴더에 평범한 JSON 파일로 내보내고 경로를 사용자에게 보여준다 — 사용자가
/// 탐색기로 그 파일을 OneDrive 동기화 폴더 등 원하는 곳에 직접 옮길 수 있고,
/// 포맷 자체(순수 JSON, 스키마 버전 포함)는 나중에 자동 동기화를 붙여도
/// 그대로 재사용 가능하다.
library;

import 'dart:convert';
import 'dart:io';

import 'plan_migration.dart';
import 'plan_repository.dart';

/// [snapshot] 을 사람이 읽기 쉬운(들여쓰기 포함) JSON 문자열로.
String exportSnapshotToJsonString(PlanSnapshot snapshot) {
  return const JsonEncoder.withIndent('  ').convert(snapshotToJson(snapshot));
}

/// [snapshot] 을 [file] 에 쓴다(덮어쓰기).
Future<void> exportSnapshotToFile(PlanSnapshot snapshot, File file) async {
  await file.writeAsString(exportSnapshotToJsonString(snapshot));
}

/// 가져오기 파싱/검증 결과. 실패 시 [error] 에 사용자에게 보여줄 메시지가 담긴다
/// (예외를 던지지 않는다 — 호출부가 다이얼로그 등으로 그대로 표시할 수 있게).
class ImportResult {
  final PlanSnapshot? snapshot;
  final String? error;

  const ImportResult.success(PlanSnapshot this.snapshot) : error = null;
  const ImportResult.failure(String this.error) : snapshot = null;

  bool get isSuccess => snapshot != null;
}

/// [raw] 문자열을 파싱/검증한다.
///
/// 검증 단계:
/// 1. 비어있지 않은지.
/// 2. 유효한 JSON 인지.
/// 3. 최상위가 Map 이고 최소한 `"nodes"` 키가 있는지(PlanBook 백업 파일 형태인지
///    최소한의 shape 확인 — 완전히 다른 JSON 파일을 실수로 불러오는 것 방지).
/// 4. 그 다음은 [snapshotFromJson] 에 위임 — schemaVersion 무관하게 마이그레이션
///    하고, 개별 노드가 깨졌으면 그 항목만 건너뛴다(기존 로드 경로와 동일 정책).
ImportResult parseImportJson(String raw) {
  if (raw.trim().isEmpty) {
    return const ImportResult.failure('빈 파일입니다.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const ImportResult.failure('올바른 JSON 형식이 아닙니다.');
  }
  if (decoded is! Map<String, Object?>) {
    return const ImportResult.failure('PlanBook 백업 파일 형식이 아닙니다.');
  }
  if (!decoded.containsKey('nodes')) {
    return const ImportResult.failure(
        'PlanBook 백업 파일 형식이 아닙니다("nodes" 필드 없음).');
  }
  return ImportResult.success(snapshotFromJson(decoded));
}

/// [file] 을 읽어 [parseImportJson] 으로 검증한다. 파일 자체를 못 읽으면
/// (없음/권한 등) 실패 사유를 담아 반환한다(예외 없음).
Future<ImportResult> readAndParseImportFile(File file) async {
  try {
    if (!await file.exists()) {
      return const ImportResult.failure('파일을 찾을 수 없습니다.');
    }
    final raw = await file.readAsString();
    return parseImportJson(raw);
  } catch (e) {
    return ImportResult.failure('파일을 읽는 중 오류가 발생했습니다: $e');
  }
}
