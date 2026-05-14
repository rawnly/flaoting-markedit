//
//  CommandBarController.swift
//  MarkEditMac
//
//  Created by Codex on 5/14/26.
//

import AppKit

@MainActor
final class CommandBarController: NSViewController {
  private let searchField = NSSearchField()
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private var allFiles = [URL]()
  private var items = [CommandItem]()

  override func loadView() {
    view = NSView(frame: CGRect(x: 0, y: 0, width: 520, height: 320))
    view.wantsLayer = true
    view.layer?.cornerRadius = 8
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

    searchField.placeholderString = "Search notes or create a note"
    searchField.focusRingType = .none
    searchField.target = self
    searchField.action = #selector(searchChanged(_:))
    searchField.translatesAutoresizingMaskIntoConstraints = false

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Command"))
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.rowHeight = 34
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(acceptSelection)
    tableView.translatesAutoresizingMaskIntoConstraints = false

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(searchField)
    view.addSubview(scrollView)

    NSLayoutConstraint.activate([
      searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
      searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      searchField.heightAnchor.constraint(equalToConstant: 32),
      scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
    ])
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    allFiles = AppVault.markdownFiles()
    searchField.stringValue = ""
    reloadItems()
    view.window?.makeFirstResponder(searchField)
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 0x35:
      dismiss(nil)
    case 0x24:
      acceptSelection()
    case 0x7D:
      moveSelection(by: 1)
    case 0x7E:
      moveSelection(by: -1)
    default:
      super.keyDown(with: event)
    }
  }
}

extension CommandBarController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    items.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = NSTableCellView()
    let textField = NSTextField(labelWithString: items[row].title)
    textField.font = .systemFont(ofSize: 13)
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

  @objc func searchChanged(_ sender: NSSearchField) {
    reloadItems()
  }

  @objc func acceptSelection() {
    let row = max(tableView.selectedRow, 0)
    guard items.indices.contains(row) else {
      return
    }

    let item = items[row]
    dismiss(nil)

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

    var nextItems = [CommandItem(title: "Open Today's Note", action: .today)]

    if !query.isEmpty {
      nextItems.append(CommandItem(title: "Create \"\(query).md\"", action: .create(query)))
    }

    nextItems.append(contentsOf: matches)
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
