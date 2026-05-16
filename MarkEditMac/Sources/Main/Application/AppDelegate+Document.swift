//
//  AppDelegate+Document.swift
//  MarkEditMac
//
//  Created by cyan on 1/15/23.
//

import AppKit

@MainActor
extension AppDelegate {
  var currentDocument: EditorDocument? {
    currentEditor?.document
  }

  var currentEditor: EditorViewController? {
    NSApp.currentEditor
  }

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    guard shouldOpenOrCreateDocument() else {
      return false
    }

    AppVault.openToday()
    return false
  }

  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()

    // Only show the secondary option based on the preference
    switch AppPreferences.General.newWindowBehavior {
    case .openDocument:
      menu.addItem(withTitle: Localized.Document.newDocument) {
        NSDocumentController.shared.newDocument(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
    case .newDocument:
      menu.addItem(withTitle: Localized.Document.openDocument) {
        sender.showOpenPanel()
      }
    }

    return menu
  }

  func createNewFile(fileName: String? = nil, initialContent: String? = nil, isIntent: Bool = false) {
    guard fileName != nil || initialContent != nil else {
      AppVault.openToday()
      return
    }

    // In EditorDocument, this is used as an external filename
    AppDocumentController.suggestedFilename = fileName

    // Activating the app also creates a new file if new window behavior is `newDocument`,
    // prevent duplicate creation from Shortcuts like `CreateNewDocumentIntent`.
    if !isIntent || (Date.timeIntervalSinceReferenceDate - States.untitledFileOpenedDate > 0.2) {
      AppDocumentController.createsUntitledDocument = true
      NSDocumentController.shared.newDocument(nil)
      AppDocumentController.createsUntitledDocument = false
    }

    if isIntent {
      NSApp.activate(ignoringOtherApps: true)
    }

    if let initialContent {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        self.currentEditor?.prepareInitialContent(initialContent)
      }
    }
  }

  func openFile(queryDict: [String: String]?) {
    if let filePath = queryDict?["path"] {
      NSWorkspace.shared.openOrReveal(url: URL(filePath: filePath))
    } else {
      NSApp.showOpenPanel()
    }
  }

  func createNewFile(queryDict: [String: String]?) {
    let fileName = queryDict?["filename"]
    let initialContent = queryDict?["initial-content"]
    createNewFile(fileName: fileName, initialContent: initialContent)
  }

  func toggleDocumentWindowVisibility() {
    // Order out immaterial windows like settings, about...
    for window in NSApp.windows where !(window is EditorWindow) {
      window.orderOut(nil)
    }

    let windows = NSApp.windows.compactMap { $0 as? EditorWindow }

    if windows.isEmpty {
      // Open a new window if we don't have any editor windows
      AppVault.openToday()
      return
    } else if windows.contains(where: { $0.isVisible && $0.isKeyWindow }) {
      // Hide only the editor window so the next toggle restores the same frame.
      windows.forEach { $0.orderOut(nil) }
      return
    } else {
      windows.first?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }
}

// MARK: - Private

private extension AppDelegate {
  enum States {
    @MainActor static var openPanelShownDate: TimeInterval = 0
    @MainActor static var untitledFileOpenedDate: TimeInterval = 0
  }

  @discardableResult
  func openOrCreateDocument(sender: NSApplication) -> Bool {
    AppVault.openToday()
    return false
  }
}
