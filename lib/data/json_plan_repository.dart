/// JSON 파일 기반 [PlanRepository] 구현.
///
/// - 저장 위치: 지정된 [directory] 아래 [fileName] 파일.
///   프로덕션에서는 path_provider 의 getApplicationSupportDirectory() 결과를 주입.
///   테스트에서는 임시 디렉터리를 주입.
/// - 원자적 쓰기: `<fileName>.tmp` 에 쓴 뒤 rename 으로 한 번에 교체.
///   rename 은 대상 파일이 존재해도 원자적으로 덮어쓰므로, 쓰다 죽어도 기존 파일은
///   손상되지 않는다(delete-then-rename 사이의 데이터 소실 창이 없다).
/// - 읽기: 파일 없음 → null. JSON 손상/파싱 실패 → null(예외 X).
///   알 수 없는 필드는 무시하고 알려진 필드만 파싱.
/// - 복구: 본 파일이 없거나 손상된 경우 같은 디렉터리의 `.tmp` 가 유효하면
///   그것으로 복구한 뒤 정상 파일로 승격한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'plan_migration.dart';
import 'plan_repository.dart';

class JsonPlanRepository implements PlanRepository {
  final Directory directory;
  final String fileName;
  final String tmpSuffix;

  JsonPlanRepository({
    required this.directory,
    this.fileName = 'plan_store.json',
    this.tmpSuffix = '.tmp',
  });

  File get _file => File('${directory.path}${Platform.pathSeparator}$fileName');
  File get _tmpFile =>
      File('${directory.path}${Platform.pathSeparator}$fileName$tmpSuffix');

  @override
  Future<PlanSnapshot?> load() async {
    // 정상 경로: 본 파일을 읽어 파싱. 성공하면 .tmp 는 건드리지 않는다(느려지지 않게).
    final main = await _readAndParse(_file);
    if (main != null) {
      return main;
    }
    // 복구 경로: 본 파일이 없거나 손상된 경우, 같은 디렉터리의 .tmp 파일이
    // 유효한 JSON 이면 그것으로 복구한다. (과거 버그로 인한 소실 상황이나
    // rename 직전 중단 등에서 살아남기 위함)
    final recovered = await _readAndParse(_tmpFile);
    if (recovered == null) {
      return null;
    }
    // 복구 성공: .tmp 를 정상 파일로 승격(rename). 최선의 노력(best-effort)이며,
    // 실패해도 이미 메모리에 로드한 데이터는 반환한다.
    try {
      if (await _tmpFile.exists()) {
        await _tmpFile.rename(_file.path);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('JsonPlanRepository: tmp promote failed: $e');
      }
    }
    return recovered;
  }

  /// [file] 를 읽어 [PlanSnapshot] 으로 파싱한다.
  /// - 파일이 없거나 비어있으면 null.
  /// - JSON 손상/파싱 실패/형식 불일치 → null(예외 X).
  /// - 알 수 없는 필드는 무시하고 알려진 필드만 파싱.
  Future<PlanSnapshot?> _readAndParse(File file) async {
    try {
      if (!await file.exists()) {
        return null;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      // 스키마 변환/파싱은 plan_migration.dart 가 담당한다.
      return snapshotFromJson(decoded);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('JsonPlanRepository: parse failed: $e');
      }
      return null;
    }
  }

  @override
  Future<void> save(PlanSnapshot snapshot) async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final payload = snapshotToJson(snapshot);
      final json = const JsonEncoder.withIndent('  ').convert(payload);
      // 1) 임시 파일에 전체 쓰기.
      await _tmpFile.writeAsString(json, flush: true);
      // 2) 원자적 교체(rename). 같은 디렉터리 내 rename 은 POSIX/Win32 모두 원자적이며,
      //    Dart 의 File.rename 은 대상 파일이 이미 존재해도 예외 없이 **덮어쓴다**
      //    (POSIX rename(2) 및 Win32 MoveFileEx(MOVEFILE_REPLACE_EXISTING) 동일).
      //    따라서 기존 파일을 미리 delete() 할 필요가 없으며, 오히려 delete() 와 rename()
      //    사이에 프로세스가 죽으면 실제 파일이 없는 상태가 되어 데이터가 소실된다.
      //    rename() 한 번으로 원자적 교체가 보장된다.
      await _tmpFile.rename(_file.path);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('JsonPlanRepository: save failed: $e');
      }
      rethrow;
    }
  }
}
