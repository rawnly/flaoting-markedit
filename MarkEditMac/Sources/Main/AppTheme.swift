//
//  AppTheme.swift
//  MarkEditMac
//
//  Created by cyan on 12/17/22.
//

import AppKit

struct AppTheme {
  let isDark: Bool
  let editorTheme: String
  // Pre-defined colors to style the window for initial launch
  let windowBackground: NSColor
  // If true, the toolbar has more tinted effect based on windowBackground,
  // usually it's for dark themes, some light themes also need this, such as solarized.
  let prefersTintedToolbar: Bool

  @MainActor static var current: Self {
    NSApplication.shared.isDarkMode ? darkTheme : lightTheme
  }

  static func withName(_ name: String) -> Self {
    allCases.first { $0.editorTheme == name } ?? (NSApplication.shared.isDarkMode ? XcodeDark : XcodeLight)
  }

  /// Get a "resolved" appearance name based on the current effective appearance.
  @MainActor var resolvedAppearance: NSAppearance? {
    NSAppearance(named: NSApp.effectiveAppearance.resolvedName(isDarkMode: isDark))
  }

  /// Trigger theme update for all editors.
  @MainActor
  func updateAppearance(animateChanges: Bool = false) {
    EditorPreloader.shared.viewControllers().forEach {
      $0.setTheme(self, animated: animateChanges)
    }
  }
}

// MARK: - Themes

extension AppTheme: CaseIterable, Hashable, CustomStringConvertible {
  static var allCases: [AppTheme] {
    [XcodeLight, XcodeDark]
  }

  static var XcodeLight: Self {
    Self(
      isDark: false,
      editorTheme: "xcode-light",
      windowBackground: NSColor(hexCode: 0xffffff),
      prefersTintedToolbar: false
    )
  }

  static var XcodeDark: Self {
    Self(
      isDark: true,
      editorTheme: "xcode-dark",
      windowBackground: NSColor(hexCode: 0x1f1f24),
      prefersTintedToolbar: true
    )
  }

  static var Dracula: Self {
    Self(
      isDark: true,
      editorTheme: "dracula",
      windowBackground: NSColor(hexCode: 0x282a36),
      prefersTintedToolbar: true
    )
  }

  static var Cobalt: Self {
    Self(
      isDark: true,
      editorTheme: "cobalt",
      windowBackground: NSColor(hexCode: 0x193549),
      prefersTintedToolbar: true
    )
  }

  static var WinterIsComingLight: Self {
    Self(
      isDark: false,
      editorTheme: "winter-is-coming-light",
      windowBackground: NSColor(hexCode: 0xffffff),
      prefersTintedToolbar: false
    )
  }

  static var WinterIsComingDark: Self {
    Self(
      isDark: true,
      editorTheme: "winter-is-coming-dark",
      windowBackground: NSColor(hexCode: 0x282822),
      prefersTintedToolbar: true
    )
  }

  static var MinimalLight: Self {
    Self(
      isDark: false,
      editorTheme: "minimal-light",
      windowBackground: NSColor(hexCode: 0xffffff),
      prefersTintedToolbar: false
    )
  }

  static var MinimalDark: Self {
    Self(
      isDark: true,
      editorTheme: "minimal-dark",
      windowBackground: NSColor(hexCode: 0x1e1e1e),
      prefersTintedToolbar: true
    )
  }

  static var SynthWave84: Self {
    Self(
      isDark: true,
      editorTheme: "synthwave84",
      windowBackground: NSColor(hexCode: 0x252335),
      prefersTintedToolbar: true
    )
  }

  static var NightOwl: Self {
    Self(
      isDark: true,
      editorTheme: "night-owl",
      windowBackground: NSColor(hexCode: 0x011627),
      prefersTintedToolbar: true
    )
  }

  static var RosePineDawn: Self {
    Self(
      isDark: false,
      editorTheme: "rose-pine-dawn",
      windowBackground: NSColor(hexCode: 0xfaf4ed),
      prefersTintedToolbar: true
    )
  }

  static var RosePine: Self {
    Self(
      isDark: true,
      editorTheme: "rose-pine",
      windowBackground: NSColor(hexCode: 0x191724),
      prefersTintedToolbar: true
    )
  }

  static var SolarizedLight: Self {
    Self(
      isDark: false,
      editorTheme: "solarized-light",
      windowBackground: NSColor(hexCode: 0xfdf6e3),
      prefersTintedToolbar: true
    )
  }

  static var SolarizedDark: Self {
    Self(
      isDark: true,
      editorTheme: "solarized-dark",
      windowBackground: NSColor(hexCode: 0x002b36),
      prefersTintedToolbar: true
    )
  }

  var description: String {
    switch self {
    case Self.XcodeLight:
      return "Xcode (Light)"
    case Self.XcodeDark:
      return "Xcode (Dark)"
    default:
      fatalError("Invalid theme was found")
    }
  }
}

// MARK: - Private

@MainActor
private extension AppTheme {
  static var lightTheme: Self {
    withName(AppPreferences.Editor.lightTheme)
  }

  static var darkTheme: Self {
    withName(AppPreferences.Editor.darkTheme)
  }
}
