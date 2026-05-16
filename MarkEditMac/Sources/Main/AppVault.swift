//
//  AppVault.swift
//  MarkEditMac
//
//  Created by Codex on 5/14/26.
//

import AppKit
import MarkEditKit

@MainActor
enum AppVault {
  static let supportedExtensions = Set(NewFilenameExtension.allCases.map(\.rawValue))

  static var vaultURL: URL? {
    resolveVaultBookmark()
  }

  static var todayFileName: String {
    let formatter = DateFormatter()
    formatter.calendar = .current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return "\(formatter.string(from: Date())).md"
  }

  static func openToday(display: Bool = true) {
    Task { @MainActor in
      do {
        let url = try ensureTodayNote()
        openDocument(at: url, display: display)
      } catch {
        NSApp.presentError(error)
      }
    }
  }

  static func ensureTodayNote() throws -> URL {
    let vaultURL = try ensureVault()
    let noteURL = vaultURL.appending(path: todayFileName, directoryHint: .notDirectory)
    try createFileIfNeeded(at: noteURL)
    return noteURL
  }

  static func ensureVault() throws -> URL {
    if let vaultURL {
      return vaultURL
    }

    guard let selectedURL = selectVault() else {
      throw VaultError.missingVault
    }

    try storeVaultBookmark(for: selectedURL)
    return selectedURL
  }

  static func openDocument(at url: URL, display: Bool = true) {
    if display, replaceCurrentDocument(with: url) {
      return
    }

    NSDocumentController.shared.openDocument(withContentsOf: url, display: display) { _, _, error in
      if let error {
        NSApp.presentError(error)
      }
    }
  }

  static func createNamedNote(named rawName: String) throws -> URL {
    let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw VaultError.emptyName
    }

    let sanitized = trimmed
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")

    let fileName = sanitized.hasSuffix(".md") ? sanitized : "\(sanitized).md"
    let url = try ensureVault().appending(path: fileName, directoryHint: .notDirectory)
    try createFileIfNeeded(at: url)
    return url
  }

  static func createNewNote() throws -> URL {
    let vaultURL = try ensureVault()
    let formatter = DateFormatter()
    formatter.calendar = .current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm"

    let baseName = formatter.string(from: Date())
    var noteURL = vaultURL.appending(path: "\(baseName).md", directoryHint: .notDirectory)
    var counter = 2

    while FileManager.default.fileExists(atPath: noteURL.path) {
      noteURL = vaultURL.appending(path: "\(baseName) \(counter).md", directoryHint: .notDirectory)
      counter += 1
    }

    try createFileIfNeeded(at: noteURL)
    return noteURL
  }

  static func openNewNote(display: Bool = true) {
    Task { @MainActor in
      do {
        openDocument(at: try createNewNote(), display: display)
      } catch {
        NSApp.presentError(error)
      }
    }
  }

  static func markdownFiles() -> [URL] {
    guard let vaultURL else {
      return []
    }

    let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
    let enumerator = FileManager.default.enumerator(
      at: vaultURL,
      includingPropertiesForKeys: keys,
      options: [.skipsPackageDescendants]
    )

    return (enumerator?.compactMap { item -> URL? in
      guard let url = item as? URL else {
        return nil
      }

      let values = try? url.resourceValues(forKeys: Set(keys))
      guard values?.isRegularFile == true, values?.isHidden != true else {
        return nil
      }

      return supportedExtensions.contains(url.pathExtension.lowercased()) ? url : nil
    } ?? [])
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
  }

  static func displayPath(for url: URL) -> String {
    guard let vaultURL else {
      return url.lastPathComponent
    }

    let relative = url.path.replacingOccurrences(of: "\(vaultURL.path)/", with: "")
    return relative == url.path ? url.lastPathComponent : relative
  }
}

// MARK: - Private

private extension AppVault {
  enum VaultError: LocalizedError {
    case missingVault
    case emptyName

    var errorDescription: String? {
      switch self {
      case .missingVault:
        return "A vault folder is required to open daily notes."
      case .emptyName:
        return "Enter a note name."
      }
    }
  }

  static func resolveVaultBookmark() -> URL? {
    guard let bookmark = AppPreferences.General.vaultBookmark else {
      return nil
    }

    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      guard !isStale else {
        AppPreferences.General.vaultBookmark = nil
        return nil
      }

      _ = url.startAccessingSecurityScopedResource()
      return url
    } catch {
      AppPreferences.General.vaultBookmark = nil
      Logger.log(.error, error.localizedDescription)
      return nil
    }
  }

  static func selectVault() -> URL? {
    let panel = NSOpenPanel()
    panel.title = "Choose Notes Vault"
    panel.message = "Choose the folder where daily notes and named notes will be stored."
    panel.prompt = "Use Vault"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false

    return panel.runModal() == .OK ? panel.url : nil
  }

  static func storeVaultBookmark(for url: URL) throws {
    AppPreferences.General.vaultBookmark = try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    _ = url.startAccessingSecurityScopedResource()
  }

  static func createFileIfNeeded(at url: URL) throws {
    guard !FileManager.default.fileExists(atPath: url.path) else {
      return
    }

    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    try Data().write(to: url, options: .withoutOverwriting)
  }

  static func replaceCurrentDocument(with url: URL) -> Bool {
    guard
      let editor = NSApp.currentEditor,
      let windowController = editor.view.window?.windowController as? EditorWindowController
    else {
      return false
    }

    if editor.document?.fileURL == url {
      editor.view.window?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return true
    }

    let previousDocument = editor.document
    previousDocument?.saveContent()

    NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { document, _, error in
      if let error {
        NSApp.presentError(error)
        return
      }

      guard let document = document as? EditorDocument else {
        return
      }

      for existingWindowController in document.windowControllers where existingWindowController !== windowController {
        existingWindowController.window?.close()
        document.removeWindowController(existingWindowController)
      }

      previousDocument?.removeWindowController(windowController)
      document.addWindowController(windowController)
      document.attach(to: editor)
      windowController.synchronizeWindowTitleWithDocumentName()
      windowController.window?.representedURL = url
      windowController.window?.makeKeyAndOrderFront(nil)

      previousDocument?.close()
      NSApp.activate(ignoringOtherApps: true)
    }

    return true
  }
}
