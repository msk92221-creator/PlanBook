/// 앱 전역 설정. 저장 파일 안에 함께 보관된다(별도 파일을 만들지 않는다).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../core/date/plan_date.dart' show kWeekStartWeekday;
import '../ui/plan/gantt_metrics.dart' show GanttZoomLevel;

/// 작업 트리 칸 폭의 기본값/허용 범위.
///
/// 최소값은 "제목과 접기 화살표가 최소한 읽히는 폭", 최대값은 "Gantt 가
/// 완전히 밀려나지 않는 폭" 기준이다.
const double kDefaultTreePaneWidth = 300.0;
const double kMinTreePaneWidth = 160.0;
const double kMaxTreePaneWidth = 900.0;

/// [value] 를 트리 칸 폭 허용 범위로 자른다. NaN/무한대는 기본값으로 되돌린다.
double clampTreePaneWidth(double value) {
  if (value.isNaN || value.isInfinite) return kDefaultTreePaneWidth;
  return value.clamp(kMinTreePaneWidth, kMaxTreePaneWidth);
}

/// 앱 화면 식별자. [AppSettings.lastScreen] 에 저장된다.
///
/// **최초 실행 기본값은 항상 [today]** 다. lastScreen 은 재실행 시 복원용이다.
enum AppScreen {
  today,
  gantt,
  calendar,
  projects,
  search;

  static AppScreen fromName(String? name) {
    if (name == null) return AppScreen.today;
    for (final v in AppScreen.values) {
      if (v.name == name) return v;
    }
    return AppScreen.today;
  }

  String get label => switch (this) {
        AppScreen.today => '오늘',
        AppScreen.gantt => '간트',
        AppScreen.calendar => '달력',
        AppScreen.projects => '프로젝트',
        AppScreen.search => '검색',
      };
}

@immutable
class AppSettings {
  /// 라이트/다크/시스템.
  final ThemeMode themeMode;

  /// Gantt 화면의 초기 줌 레벨.
  final GanttZoomLevel defaultZoom;

  /// 마지막으로 본 화면(재실행 시 복원). 최초 실행 기본값은 [AppScreen.today].
  final AppScreen lastScreen;

  /// 주 시작 요일 (DateTime.monday == 1). 기본은 월요일.
  final int weekStart;

  /// 기본 프로젝트 5개를 이미 시드했는지.
  /// **사용자가 기본 프로젝트를 지운 뒤 다시 생성되지 않게 하는 플래그다.**
  final bool seededDefaultProjects;

  /// true 면 앱 재시작 시 [lastScreen] 을 복원한다. **기본값은 false** —
  /// 정책상 "앱 기본 진입 화면은 항상 Today" 이고, 마지막 화면 복원은
  /// 사용자가 설정에서 명시적으로 켜야 하는 선택 기능이다.
  final bool restoreLastScreen;

  /// Gantt 화면 왼쪽 작업 트리 칸의 폭(px). 사용자가 경계선을 끌어 조절한다.
  /// 제목이나 기간이 잘려 보일 때 넓힐 수 있어야 하므로 저장 대상이다.
  /// 범위는 [kMinTreePaneWidth]~[kMaxTreePaneWidth] 로 강제한다 — 저장 파일이
  /// 손상돼 이상한 값이 들어와도 한쪽 칸이 사라지지 않게.
  final double treePaneWidth;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.defaultZoom = GanttZoomLevel.day,
    this.lastScreen = AppScreen.today,
    this.weekStart = kWeekStartWeekday,
    this.seededDefaultProjects = false,
    this.restoreLastScreen = false,
    this.treePaneWidth = kDefaultTreePaneWidth,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    GanttZoomLevel? defaultZoom,
    AppScreen? lastScreen,
    int? weekStart,
    bool? seededDefaultProjects,
    bool? restoreLastScreen,
    double? treePaneWidth,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        defaultZoom: defaultZoom ?? this.defaultZoom,
        lastScreen: lastScreen ?? this.lastScreen,
        weekStart: weekStart ?? this.weekStart,
        seededDefaultProjects:
            seededDefaultProjects ?? this.seededDefaultProjects,
        restoreLastScreen: restoreLastScreen ?? this.restoreLastScreen,
        treePaneWidth: treePaneWidth == null
            ? this.treePaneWidth
            : clampTreePaneWidth(treePaneWidth),
      );

  Map<String, Object?> toJson() => {
        'themeMode': themeMode.name,
        'defaultZoom': defaultZoom.name,
        'lastScreen': lastScreen.name,
        'weekStart': weekStart,
        'seededDefaultProjects': seededDefaultProjects,
        'restoreLastScreen': restoreLastScreen,
        'treePaneWidth': treePaneWidth,
      };

  /// 알려진 필드만 파싱하고 알 수 없는 필드는 무시한다.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    final rawWeek = json['weekStart'];
    final week = rawWeek is num
        ? rawWeek.toInt()
        : int.tryParse(rawWeek?.toString() ?? '') ?? kWeekStartWeekday;
    final rawPane = json['treePaneWidth'];
    final pane = rawPane is num
        ? rawPane.toDouble()
        : double.tryParse(rawPane?.toString() ?? '') ?? kDefaultTreePaneWidth;
    return AppSettings(
      themeMode: _themeFromName(json['themeMode']?.toString()),
      defaultZoom: _zoomFromName(json['defaultZoom']?.toString()),
      lastScreen: AppScreen.fromName(json['lastScreen']?.toString()),
      weekStart: (week >= 1 && week <= 7) ? week : kWeekStartWeekday,
      seededDefaultProjects: json['seededDefaultProjects'] == true,
      restoreLastScreen: json['restoreLastScreen'] == true,
      treePaneWidth: clampTreePaneWidth(pane),
    );
  }

  static ThemeMode _themeFromName(String? name) {
    for (final v in ThemeMode.values) {
      if (v.name == name) return v;
    }
    return ThemeMode.system;
  }

  static GanttZoomLevel _zoomFromName(String? name) {
    for (final v in GanttZoomLevel.values) {
      if (v.name == name) return v;
    }
    return GanttZoomLevel.day;
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.defaultZoom == defaultZoom &&
      other.lastScreen == lastScreen &&
      other.weekStart == weekStart &&
      other.seededDefaultProjects == seededDefaultProjects &&
      other.restoreLastScreen == restoreLastScreen &&
      other.treePaneWidth == treePaneWidth;

  @override
  int get hashCode => Object.hash(
        themeMode,
        defaultZoom,
        lastScreen,
        weekStart,
        seededDefaultProjects,
        restoreLastScreen,
        treePaneWidth,
      );
}
