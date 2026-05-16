//
//  GeneralSettingsView.swift
//  MarkEditMac
//
//  Created by cyan on 1/26/23.
//

import SwiftUI
import SettingsUI
import MarkEditKit

@MainActor
struct GeneralSettingsView: View {
  @State private var appearance = AppPreferences.General.appearance
  @State private var newWindowBehavior = AppPreferences.General.newWindowBehavior
  @State private var quitAlwaysKeepsWindows = AppPreferences.General.quitAlwaysKeepsWindows
  @State private var newFilenameExtension = AppPreferences.General.newFilenameExtension
  @State private var defaultTextEncoding = AppPreferences.General.defaultTextEncoding
  @State private var defaultLineEndings = AppPreferences.General.defaultLineEndings
  @State private var hotKeyEnabled = AppPreferences.General.mainWindowHotKeyEnabled
  @State private var hotKeyKey = AppPreferences.General.mainWindowHotKeyKey
  @State private var hotKeyShift = AppPreferences.General.mainWindowHotKeyShift
  @State private var hotKeyControl = AppPreferences.General.mainWindowHotKeyControl
  @State private var hotKeyOption = AppPreferences.General.mainWindowHotKeyOption
  @State private var hotKeyCommand = AppPreferences.General.mainWindowHotKeyCommand

  var body: some View {
    SettingsForm {
      Section {
        Picker(Localized.Settings.appearance, selection: $appearance) {
          Text(Localized.Settings.system).tag(Appearance.system)
          Divider()
          Text(Localized.Settings.light).tag(Appearance.light)
          Text(Localized.Settings.dark).tag(Appearance.dark)
        }
        .onChange(of: appearance) {
          NSApp.appearance = appearance.resolved()
          AppPreferences.General.appearance = appearance
        }
        .formMenuPicker()

        Picker(Localized.Settings.newWindowBehavior, selection: $newWindowBehavior) {
          Text(Localized.Document.openDocument).tag(NewWindowBehavior.openDocument)
          Text(Localized.Document.newDocument).tag(NewWindowBehavior.newDocument)
        }
        .onChange(of: newWindowBehavior) {
          AppPreferences.General.newWindowBehavior = newWindowBehavior
        }
        .formMenuPicker()

        Toggle(Localized.Settings.quitAlwaysKeepsWindows, isOn: $quitAlwaysKeepsWindows)
          .onChange(of: quitAlwaysKeepsWindows) {
            AppPreferences.General.quitAlwaysKeepsWindows = quitAlwaysKeepsWindows
          }
          .formLabel(Localized.Settings.windowRestoration)
          .formBreathingInset()
      }

      Section {
        Toggle("Enable global shortcut", isOn: $hotKeyEnabled)
          .onChange(of: hotKeyEnabled) {
            AppPreferences.General.mainWindowHotKeyEnabled = hotKeyEnabled
          }
          .formLabel("Notes window")
          .formBreathingInset()

        TextField("Key", text: $hotKeyKey)
          .frame(width: 72)
          .onChange(of: hotKeyKey) {
            let normalized = hotKeyKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            hotKeyKey = String(normalized.prefix(1))
            AppPreferences.General.mainWindowHotKeyKey = hotKeyKey
          }
          .formLabel("Shortcut key")

        HStack {
          Toggle("Shift", isOn: $hotKeyShift)
            .onChange(of: hotKeyShift) {
              AppPreferences.General.mainWindowHotKeyShift = hotKeyShift
            }
          Toggle("Control", isOn: $hotKeyControl)
            .onChange(of: hotKeyControl) {
              AppPreferences.General.mainWindowHotKeyControl = hotKeyControl
            }
          Toggle("Option", isOn: $hotKeyOption)
            .onChange(of: hotKeyOption) {
              AppPreferences.General.mainWindowHotKeyOption = hotKeyOption
            }
          Toggle("Command", isOn: $hotKeyCommand)
            .onChange(of: hotKeyCommand) {
              AppPreferences.General.mainWindowHotKeyCommand = hotKeyCommand
            }
        }
        .formLabel("Modifiers")
        .formBreathingInset()
      }

      Section {
        Picker(Localized.Settings.newFilenameExtension, selection: $newFilenameExtension) {
          ForEach(NewFilenameExtension.allCases, id: \.self) {
            Text($0.rawValue).tag($0)
          }
        }
        .onChange(of: newFilenameExtension) {
          AppPreferences.General.newFilenameExtension = newFilenameExtension
        }
        .formMenuPicker()

        Picker(Localized.Settings.defaultTextEncoding, selection: $defaultTextEncoding) {
          ForEach(EditorTextEncoding.allCases, id: \.self) {
            Text($0.description)

            if EditorTextEncoding.groupingCases.contains($0) {
              Divider()
            }
          }
        }
        .onChange(of: defaultTextEncoding) {
          AppPreferences.General.defaultTextEncoding = defaultTextEncoding
        }
        .formMenuPicker()

        Picker(Localized.Settings.defaultLineEndings, selection: $defaultLineEndings) {
          Text(Localized.Settings.macOSLineEndings).tag(LineEndings.lf)
          Text(Localized.Settings.windowsLineEndings).tag(LineEndings.crlf)
          Text(Localized.Settings.classicMacLineEndings).tag(LineEndings.cr)
        }
        .onChange(of: defaultLineEndings) {
          AppPreferences.General.defaultLineEndings = defaultLineEndings
        }
        .formMenuPicker()
      }
    }
  }
}
