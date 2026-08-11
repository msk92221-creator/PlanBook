/// 이 기기의 동기화 상태 — 마지막으로 성공한 동기화의 흔적.
///
/// **동기화되는 데이터 파일에 넣지 않고 기기 로컬에만 둔다.** 이 값은 "이
/// 기기가 어디까지 맞춰놨는가" 라서 기기마다 다르다. 같이 동기화하면 기기 A 의
/// 진행 상황이 기기 B 를 덮어써서 판단이 망가진다.
///
/// [lastSyncedContentHash] 는 "마지막 동기화 이후 이 기기에서 내용이
/// 바뀌었는가" 를 알아내는 데 쓴다. [PlanStore] 의 dirty 플래그는 "디스크에
/// 저장했는가" 라서 목적이 다르다 — 저장은 끝났지만 아직 올리지 않은 상태가
/// 얼마든지 있기 때문에, 내용 해시를 따로 기억해야 한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String _kSyncStateFileName = 'sync_state.json';

class SyncState {
  /// 마지막으로 맞춰놓은 원격 파일의 eTag. 한 번도 동기화 안 했으면 null.
  final String? lastSyncedETag;

  /// 그때 올리거나 받은 내용의 해시.
  final String? lastSyncedContentHash;

  /// 마지막 성공 시각(표시용).
  final DateTime? lastSyncedAt;

  const SyncState({
    this.lastSyncedETag,
    this.lastSyncedContentHash,
    this.lastSyncedAt,
  });

  static const SyncState never = SyncState();

  /// [content] 가 마지막 동기화 내용과 다른가(= 이 기기에서 바뀌었는가).
  /// 한 번도 동기화한 적이 없으면, 내용이 있다는 것 자체가 변경이다.
  bool hasLocalChanges(String content) =>
      lastSyncedContentHash != hashContent(content);

  Map<String, Object?> toJson() => {
        'lastSyncedETag': lastSyncedETag,
        'lastSyncedContentHash': lastSyncedContentHash,
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      };

  factory SyncState.fromJson(Map<String, Object?> json) => SyncState(
        lastSyncedETag: json['lastSyncedETag']?.toString(),
        lastSyncedContentHash: json['lastSyncedContentHash']?.toString(),
        lastSyncedAt:
            DateTime.tryParse(json['lastSyncedAt']?.toString() ?? ''),
      );

  @override
  bool operator ==(Object other) =>
      other is SyncState &&
      other.lastSyncedETag == lastSyncedETag &&
      other.lastSyncedContentHash == lastSyncedContentHash &&
      other.lastSyncedAt == lastSyncedAt;

  @override
  int get hashCode =>
      Object.hash(lastSyncedETag, lastSyncedContentHash, lastSyncedAt);
}

/// 내용 지문. 바이트가 같으면 같은 값이 나온다.
String hashContent(String content) =>
    sha256.convert(utf8.encode(content)).toString();

File _stateFile(Directory localDir) =>
    File('${localDir.path}${Platform.pathSeparator}$_kSyncStateFileName');

/// 저장된 동기화 상태를 읽는다. 없거나 손상됐으면 [SyncState.never]
/// (예외 X — 상태 파일이 깨졌다고 앱을 못 쓰게 만들 이유가 없다. 최악의 경우
/// "한 번도 동기화 안 한 것" 으로 보고 다시 맞추면 된다).
Future<SyncState> loadSyncState(Directory localDir) async {
  try {
    final file = _stateFile(localDir);
    if (!await file.exists()) return SyncState.never;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return SyncState.never;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return SyncState.never;
    return SyncState.fromJson(decoded);
  } catch (_) {
    return SyncState.never;
  }
}

Future<void> saveSyncState(Directory localDir, SyncState state) async {
  if (!await localDir.exists()) {
    await localDir.create(recursive: true);
  }
  await _stateFile(localDir).writeAsString(jsonEncode(state.toJson()));
}
