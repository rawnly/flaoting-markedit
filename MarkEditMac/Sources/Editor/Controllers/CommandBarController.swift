//
//  CommandBarController.swift
//  MarkEditMac
//
//  Created by Codex on 5/14/26.
//

import AppKit

@MainActor
final class CommandBarController: NSViewController {
  let searchField = CommandBarSearchField()
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let effectView = NSVisualEffectView()
  private let divider = NSBox()
  private var allFiles = [URL]()
  private var items = [CommandItem]()

  override func loadView() {
    view = NSView(frame: CGRect(x: 0, y: 0, width: 540, height: 340))
    view.wantsLayer = true
    view.layer?.cornerRadius = 12
    view.layer?.masksToBounds = true

    effectView.material = .hudWindow
    effectView.blendingMode = .behindWindow
    effectView.state = AppDesign.reduceTransparency ? .inactive : .followsWindowActiveState
    effectView.alphaValue = AppDesign.reduceTransparency ? 1.0 : 0.98
    effectView.translatesAutoresizingMaskIntoConstraints = false
    effectView.wantsLayer = true
    effectView.layer?.cornerRadius = 12
    effectView.layer?.masksToBounds = true

    searchField.placeholderString = "Search notes or create a note"
    searchField.focusRingType = .none
    searchField.controlSize = .large
    searchField.font = .systemFont(ofSize: 17)
    searchField.isBordered = false
    searchField.drawsBackground = false
    if let searchCell = searchField.cell as? NSSearchFieldCell {
      searchCell.searchButtonCell = nil
      searchCell.cancelButtonCell = nil
    }
    searchField.delegate = self
    searchField.onKeyDown = { [weak self] event in
      self?.handleKeyDown(event) == true
    }
    searchField.translatesAutoresizingMaskIntoConstraints = false

    divider.boxType = .separator
    divider.translatesAutoresizingMaskIntoConstraints = false

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Command"))
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.rowHeight = 36
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.backgroundColor = .clear
    tableView.usesAlternatingRowBackgroundColors = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(acceptSelection)
    tableView.translatesAutoresizingMaskIntoConstraints = false

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    if #available(macOS 11.0, *) {
      scrollView.automaticallyAdjustsContentInsets = false
    }
    scrollView.contentInsets = NSEdgeInsetsZero
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(effectView)
    effectView.addSubview(searchField)
    effectView.addSubview(divider)
    effectView.addSubview(scrollView)

    NSLayoutConstraint.activate([
      effectView.topAnchor.constraint(equalTo: view.topAnchor),
      effectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      effectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      searchField.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 12),
      searchField.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
      searchField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
      searchField.heightAnchor.constraint(equalToConstant: 32),
      divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
      divider.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
      divider.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 4),
      scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -12),
    ])
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    allFiles = AppVault.markdownFiles()
    searchField.stringValue = ""
    reloadItems()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    focusSearchField()
  }

  override func keyDown(with event: NSEvent) {
    if !handleKeyDown(event) {
      super.keyDown(with: event)
    }
  }

  func focusSearchField() {
    view.window?.makeFirstResponder(searchField)
    searchField.currentEditor()?.selectAll(nil)
  }
}

extension CommandBarController: NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.moveDown(_:)):
      moveSelection(by: 1)
      return true
    case #selector(NSResponder.moveUp(_:)):
      moveSelection(by: -1)
      return true
    case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
      acceptSelection()
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      view.window?.close()
      return true
    default:
      return false
    }
  }

  func controlTextDidChange(_ notification: Notification) {
    reloadItems()
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    items.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = NSTableCellView()
    let textField = NSTextField(labelWithString: items[row].title)
    textField.font = .systemFont(ofSize: 13.5)
    textField.lineBreakMode = .byTruncatingMiddle
    textField.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(textField)
    cell.textField = textField

    NSLayoutConstraint.activate([
      textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
      textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
      textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])

    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard tableView.selectedRow >= 0 else {
      return
    }
  }
}

// MARK: - Private

private extension CommandBarController {
  struct CommandItem {
    enum Action {
      case today
      case open(URL)
      case create(String)
    }

    let title: String
    let action: Action
  }

  func handleKeyDown(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 0x35:
      view.window?.close()
      return true
    case 0x24, 0x30:
      acceptSelection()
      return true
    case 0x7D:
      moveSelection(by: 1)
      return true
    case 0x7E:
      moveSelection(by: -1)
      return true
    default:
      return false
    }
  }

  @objc func acceptSelection() {
    let row = max(tableView.selectedRow, 0)
    guard items.indices.contains(row) else {
      return
    }

    let item = items[row]
    view.window?.close()

    do {
      switch item.action {
      case .today:
        AppVault.openToday()
      case .open(let url):
        AppVault.openDocument(at: url)
      case .create(let name):
        AppVault.openDocument(at: try AppVault.createNamedNote(named: name))
      }
    } catch {
      NSApp.presentError(error)
    }
  }

  func reloadItems() {
    let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = allFiles.filter { fuzzyMatches(query, in: AppVault.displayPath(for: $0)) }
      .prefix(20)
      .map { CommandItem(title: AppVault.displayPath(for: $0), action: .open($0)) }

    var nextItems = [CommandItem]()

    if query.isEmpty {
      nextItems.append(CommandItem(title: "Open Today's Note", action: .today))
    }

    nextItems.append(contentsOf: matches)

    if !query.isEmpty {
      nextItems.append(CommandItem(title: "Create \"\(query).md\"", action: .create(query)))
    }

    items = nextItems
    tableView.reloadData()
    tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  }

  func moveSelection(by offset: Int) {
    guard !items.isEmpty else {
      return
    }

    let current = tableView.selectedRow < 0 ? 0 : tableView.selectedRow
    let next = min(max(current + offset, 0), items.count - 1)
    tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
    tableView.scrollRowToVisible(next)
  }

  func fuzzyMatches(_ query: String, in candidate: String) -> Bool {
    guard !query.isEmpty else {
      return true
    }

    let loweredQuery = query.lowercased()
    var queryIndex = loweredQuery.startIndex
    let lowered = candidate.lowercased()

    for character in lowered where character == loweredQuery[queryIndex] {
      loweredQuery.formIndex(after: &queryIndex)
      if queryIndex == loweredQuery.endIndex {
        return true
      }
    }

    return false
  }
}

final class CommandBarPanel: NSPanel {
  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    false
  }
}

final class CommandBarSearchField: NSSearchField {
  override static var cellClass: AnyClass? {
    get { CommandBarSearchFieldCell.self }
    set {}
  }

  var onKeyDown: ((NSEvent) -> Bool)?

  override func keyDown(with event: NSEvent) {
    if onKeyDown?(event) == true {
      return
    }

    super.keyDown(with: event)
  }
}

final class CommandBarSearchFieldCell: NSSearchFieldCell {
  override func searchTextRect(forBounds bounds: NSRect) -> NSRect {
    let rect = super.searchTextRect(forBounds: bounds)
    return centeredRect(rect, in: bounds)
  }

  override func drawingRect(forBounds rect: NSRect) -> NSRect {
    let drawing = super.drawingRect(forBounds: rect)
    return centeredRect(drawing, in: rect)
  }

  private func centeredRect(_ rect: NSRect, in bounds: NSRect) -> NSRect {
    NSRect(
      x: rect.minX + 2,
      y: bounds.midY - rect.height / 2,
      width: max(rect.width - 2, 0),
      height: rect.height
    )
  }
}
