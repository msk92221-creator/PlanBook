/// 동기화 판단 로직 (순수 함수 — 네트워크/파일 I/O 없음).
///
/// **왜 분리했나**: "언제 올리고, 언제 내리고, 언제 충돌인가"는 동기화에서
/// 유일하게 틀리기 쉬운 부분인데, Graph API 호출과 뒤섞여 있으면 테스트가
/// 사실상 불가능해진다. 그래서 판단은 여기서 값만 보고 내리고, 실제 통신은
/// 호출부가 한다.
///
/// **기준이 되는 값 3개**:
/// - `remoteTag`   : 지금 OneDrive 에 있는 파일의 eTag. 파일이 없으면 null.
/// - `syncedTag`   : 마지막으로 성공한 동기화 시점의 eTag. 한 번도 동기화한
///                   적이 없으면 null.
/// - `localChanged`: 마지막 동기화 이후 이 기기에서 데이터가 바뀌었는지.
///
/// `remoteTag != syncedTag` 는 "내가 마지막으로 본 뒤 **다른 기기가** 올렸다"
/// 는 뜻이다. 여기에 `localChanged` 까지 겹치면 양쪽이 갈라진 것이므로
/// 자동으로 한쪽을 버리지 않고 [SyncAction.conflict] 로 사용자에게 넘긴다.
library;

enum SyncAction {
  /// 이미 최신 — 할 일 없음.
  upToDate,

  /// 이 기기 데이터를 올린다.
  upload,

  /// 원격 데이터를 받아 이 기기에 적용한다.
  download,

  /// 양쪽이 갈라졌다. **자동으로 처리하지 않고** 사용자에게 물어야 한다.
  conflict,
}

/// 다음에 무엇을 할지 결정한다.
///
/// [remoteTag] 가 null 이면 OneDrive 에 아직 파일이 없다는 뜻이다. 이때는
/// 올릴 게 있으면 올리고(=[SyncAction.upload]), 없으면 할 일이 없다.
/// **한 번 동기화한 뒤 원격 파일이 사라진 경우**(syncedTag 는 있는데
/// remoteTag 가 null)도 올리기로 본다 — 다른 기기에서 지웠을 수 있지만,
/// 지웠다는 이유로 이 기기 데이터를 함께 날리는 것보다 복구가 안전하다.
SyncAction decideSyncAction({
  required String? remoteTag,
  required String? syncedTag,
  required bool localChanged,
}) {
  if (remoteTag == null) {
    // 원격에 파일이 없다. 올릴 게 있으면 올린다.
    // (한 번도 동기화 안 했고 로컬도 안 바뀐 첫 실행이면 올릴 것도 없다)
    return (localChanged || syncedTag != null)
        ? SyncAction.upload
        : SyncAction.upToDate;
  }

  final remoteMovedOn = remoteTag != syncedTag;

  if (remoteMovedOn && localChanged) {
    // 양쪽 다 바뀌었다 — 한쪽을 말없이 버리면 안 된다.
    return SyncAction.conflict;
  }
  if (remoteMovedOn) {
    return SyncAction.download;
  }
  if (localChanged) {
    return SyncAction.upload;
  }
  return SyncAction.upToDate;
}

/// 충돌이 났을 때 사용자가 고를 수 있는 선택지.
///
/// 어느 쪽을 고르든 **버려지는 쪽을 먼저 백업 파일로 남긴다**(호출부 책임).
/// 동기화 때문에 사용자가 쓴 내용이 흔적 없이 사라지는 일은 없어야 한다.
enum ConflictResolution {
  /// 이 기기 데이터를 올려서 원격을 덮어쓴다.
  keepLocal,

  /// 원격 데이터를 받아 이 기기를 덮어쓴다.
  keepRemote,
}
