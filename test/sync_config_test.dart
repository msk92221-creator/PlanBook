import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/sync_config.dart';

Directory _tmp(String n) =>
    Directory.systemTemp.createTempSync('planbook_sync_config_$n');

void main() {
  group('SyncConfig.toJson / fromJson', () {
    test('폴더 경로가 있으면 isEnabled 는 true', () {
      const cfg = SyncConfig(folderPath: r'C:\Users\me\OneDrive');
      expect(cfg.isEnabled, isTrue);
      final restored = SyncConfig.fromJson(cfg.toJson());
      expect(restored.folderPath, cfg.folderPath);
      expect(restored, cfg);
    });

    test('폴더 경로가 없으면(null) isEnabled 는 false', () {
      const cfg = SyncConfig();
      expect(cfg.isEnabled, isFalse);
      expect(SyncConfig.fromJson(cfg.toJson()).isEnabled, isFalse);
    });

    test('빈 문자열 폴더 경로도 isEnabled 는 false', () {
      const cfg = SyncConfig(folderPath: '');
      expect(cfg.isEnabled, isFalse);
    });
  });

  group('loadSyncConfig / saveSyncConfig (실제 파일 I/O)', () {
    test('설정 파일이 없으면 빈 설정(동기화 꺼짐)을 반환한다', () async {
      final dir = _tmp('missing');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final cfg = await loadSyncConfig(dir);
      expect(cfg.isEnabled, isFalse);
    });

    test('저장 후 다시 읽으면 같은 값을 돌려준다', () async {
      final dir = _tmp('roundtrip');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      await saveSyncConfig(dir, const SyncConfig(folderPath: r'D:\OneDrive'));
      final cfg = await loadSyncConfig(dir);

      expect(cfg.folderPath, r'D:\OneDrive');
      expect(cfg.isEnabled, isTrue);
    });

    test('디렉터리가 없어도 saveSyncConfig 가 만들어서 저장한다', () async {
      final base = _tmp('create_dir_base');
      addTearDown(() {
        if (base.existsSync()) base.deleteSync(recursive: true);
      });
      final dir = Directory(
          '${base.path}${Platform.pathSeparator}nested${Platform.pathSeparator}PlanBook');
      expect(dir.existsSync(), isFalse);

      await saveSyncConfig(dir, const SyncConfig(folderPath: '/x'));

      expect(dir.existsSync(), isTrue);
      final cfg = await loadSyncConfig(dir);
      expect(cfg.folderPath, '/x');
    });

    test('손상된 설정 파일은 예외 없이 빈 설정으로 처리된다', () async {
      final dir = _tmp('corrupt');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      await dir.create(recursive: true);
      final file =
          File('${dir.path}${Platform.pathSeparator}sync_config.json');
      await file.writeAsString('{ not valid json ,,');

      final cfg = await loadSyncConfig(dir);
      expect(cfg.isEnabled, isFalse);
    });

    test('동기화 해제(빈 설정) 저장 후에는 다시 꺼짐 상태로 읽힌다', () async {
      final dir = _tmp('disable');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      await saveSyncConfig(dir, const SyncConfig(folderPath: r'C:\OneDrive'));
      expect((await loadSyncConfig(dir)).isEnabled, isTrue);

      await saveSyncConfig(dir, const SyncConfig());
      expect((await loadSyncConfig(dir)).isEnabled, isFalse);
    });
  });

  group('syncDataDir / resolveDataDir', () {
    test('syncDataDir 는 고른 폴더 아래 PlanBook 하위 폴더를 가리킨다', () {
      final dir = syncDataDir(r'C:\Users\me\OneDrive');
      expect(dir.path,
          '${r'C:\Users\me\OneDrive'}${Platform.pathSeparator}PlanBook');
    });

    test('동기화 꺼짐이면 resolveDataDir 는 localDir 그대로', () {
      final local = Directory(r'C:\local\PlanBook');
      final dir = resolveDataDir(local, const SyncConfig());
      expect(dir.path, local.path);
    });

    test('동기화 켜짐이면 resolveDataDir 는 동기화 폴더 아래 PlanBook', () {
      final local = Directory(r'C:\local\PlanBook');
      final dir = resolveDataDir(
          local, const SyncConfig(folderPath: r'C:\Users\me\OneDrive'));
      expect(dir.path, syncDataDir(r'C:\Users\me\OneDrive').path);
    });
  });
}
