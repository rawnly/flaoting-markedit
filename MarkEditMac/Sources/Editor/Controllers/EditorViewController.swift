//
//  EditorViewController.swift
//  MarkEditMac
//
//  Created by cyan on 12/12/22.

import AppKit
import AppKitControls
import WebKit
import MarkEditCore
import MarkEditKit
import Statistics
import TextCompletion

private enum EditorBundledScripts {
  static let vimStatusChrome = #"""
    (() => {
      const style = document.createElement("style");
      style.textContent = `
        .cm-editor { position: relative; }
        .cm-panels-bottom {
          position: absolute !important;
          left: auto !important;
          right: 92px !important;
          bottom: 12px !important;
          z-index: 20;
          border: 0 !important;
          background: transparent !important;
          pointer-events: none;
        }
        .cm-panels-bottom:has(input) {
          left: 12px !important;
          right: 12px !important;
        }
        .cm-vim-panel {
          min-height: 0 !important;
          display: inline-flex !important;
          align-items: center;
          padding: 3px 8px !important;
          border: 1px solid rgba(255, 255, 255, .12);
          border-radius: 6px;
          background: rgba(32, 32, 36, .76);
          box-shadow: 0 2px 8px rgba(0, 0, 0, .22);
          backdrop-filter: blur(18px);
          color: rgba(255, 255, 255, .86);
          pointer-events: auto;
        }
        .cm-vim-panel span {
          font: 11px ui-monospace, SFMono-Regular, Menlo, monospace !important;
          line-height: 14px !important;
        }
        .cm-vim-panel input { color: inherit !important; }
        .cm-vim-panel span[style*="flex"] { display: none !important; }
      `;
      document.head.appendChild(style);

      const modes = {
        NORMAL: "N",
        INSERT: "I",
        VISUAL: "V",
        "VISUAL BLOCK": "B",
        REPLACE: "R",
      };

      function compactMode(panel) {
        panel.querySelectorAll(".cm-vim-panel span").forEach((span) => {
          const match = span.textContent?.match(/^--(.+)--$/);
          if (!match) return;

          const mode = match[1].replace(/\(C-O\)$/, "").replace(/\s+/g, " ").trim();
          span.textContent = modes[mode] || mode.charAt(0) || "";
        });
      }

      MarkEdit.onEditorReady(({ dom }) => {
        const panel = dom.querySelector(".cm-panels-bottom");
        if (!panel) return;

        compactMode(panel);
        new MutationObserver(() => compactMode(panel)).observe(panel, {
          childList: true,
          subtree: true,
          characterData: true,
        });
      });
    })();
  """#
}

final class EditorViewController: NSViewController {
  var hasFinishedLoading = false {
    didSet {
      loadingContinuations.forEach { $0.resume() }
      loadingContinuations.removeAll()
    }
  }

  var hasUnfinishedAnimations = false
  var hasBeenEdited = false
  var mouseExitedWindow = false
  var nativeSearchQueryChanged = false
  var bottomPanelHeight: Double = 0
  var initialContent: String?
  // Use windowBackgroundColor for base background color — ensures classic Mac appearance with subtle vibrancy but no extreme transparency
  var webBackgroundColor = NSColor.windowBackgroundColor
  var localEventMonitor: Any?
  var noteAutosaveTimer: Timer?
  var textBoxInputObserver: Any?
  var writingToolsObservation: NSKeyValueObservation?
  var safeAreaObservation: NSKeyValueObservation?
  var userDefinedMenuItems = [EditorMenuItem]()

  weak var presentedMenu: NSMenu?
  weak var presentedPopover: NSPopover?
  var commandBarWindow: NSWindow?
  var commandBarCloseObserver: Any?
  var commandBarEventMonitor: Any?

  var editorText: String? {
    get async {
      guard hasFinishedLoading else {
        return nil
      }

      return try? await bridge.core.getEditorText()
    }
  }

  var tableOfContents: [HeadingInfo]? {
    get async {
      guard hasFinishedLoading else {
        return nil
      }

      return try? await bridge.toc.getTableOfContents()
    }
  }

  /// Whether the content is editable, the user can toggle the read-only state at any time.
  var isReadOnlyMode: Bool {
    get {
      document?.isReadOnlyMode ?? false
    }
    set {
      document?.isReadOnlyMode = newValue
    }
  }

  lazy var bridge = WebModuleBridge(
    webView: webView
  )

  var document: EditorDocument? {
    representedObject as? EditorDocument
  }

  var spellChecker: NSSpellChecker {
    NSSpellChecker.shared
  }

  var isFindPanelFirstResponder: Bool {
    guard findPanel.mode != .hidden else {
      return false
    }

    return findPanel.isFirstResponder || replacePanel.isFirstResponder
  }

  // Custom views to apply modern effects (either glass, blur, or visual effect) to the title bar,
  // safely supporting both NSVisualEffectView and NSGlassEffectView.
  let modernBackgroundView = NSView()
  let modernEffectView: NSView = {
    let effectView = AppDesign.modernEffectView.init()
    if let blurView = effectView as? NSVisualEffectView {
      blurView.material = .contentBackground
      blurView.blendingMode = .behindWindow
      blurView.state = .followsWindowActiveState
    }
    if #available(macOS 26.0, *), let glassView = effectView as? NSGlassEffectView {
      // Configure glass-specific properties as needed
    }
    effectView.wantsLayer = true
    // Avoid reducing alpha to prevent excessive translucency.
    effectView.alphaValue = 1.0
    return effectView
  }()
  let modernTintedView = NSView()
  let modernDividerView = DividerView()

  // Height constraint of the effect view, depending on the panel state
  private(set) lazy var modernEffectHeight: NSLayoutConstraint = {
    let anchor = modernEffectView.heightAnchor
    return anchor.constraint(equalToConstant: 0)
  }()

  private(set) lazy var findPanel = {
    let panel = EditorFindPanel()
    panel.delegate = self
    return panel
  }()

  private(set) lazy var replacePanel = {
    let panel = EditorReplacePanel()
    panel.delegate = self
    return panel
  }()

  private(set) lazy var panelDivider = DividerView()

  private(set) lazy var statusView = {
    let view = EditorStatusView { [weak self] in
      self?.showGotoLineWindow(nil)
    }

    view.isHidden = !AppPreferences.Editor.showSelectionStatus
    return view
  }()

  private(set) lazy var focusTrackingView = FocusTrackingView()

  private(set) lazy var webView: WKWebView = {
    let modules = NativeModules(modules: [
      EditorModuleCore(delegate: self),
      EditorModuleCompletion(delegate: self),
      EditorModulePreview(delegate: self),
      EditorModuleTokenizer(),
      EditorModuleAPI(delegate: self),
      EditorModuleFoundationModels(delegate: self),
      EditorModuleTranslation(),
    ])

    let handler = EditorMessageHandler(modules: modules)
    let controller = WKUserContentController()
    controller.addScriptMessageHandler(handler, contentWorld: .page, name: "bridge")

    let bundledScripts = AppPreferences.Editor.vimMotions ? [
      Bundle.main.fileContents(named: "dot-vim", extension: "js"),
      EditorBundledScripts.vimStatusChrome,
    ] : []
    let scripts = bundledScripts + [
      AppCustomization.editorScript.fileContents,
    ] + AppCustomization.scriptsDirectory.directoryContents

    scripts.forEach {
      controller.addUserScript(WKUserScript(
        source: $0,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
      ))
    }

    let config: WKWebViewConfiguration = .newConfig(disableCors: AppRuntimeConfig.disableCorsRestrictions)
    config.userContentController = controller
    config.applicationNameForUserAgent = "\(ProcessInfo.processInfo.userAgent) \(Bundle.main.userAgent)"
    config.allowsInlinePredictions = NSSpellChecker.InlineCompletion.webKitEnabled

    let chunkLoader = EditorChunkLoader()
    let imageLoader = EditorImageLoader { [weak self] in
      self?.document?.baseURL
    }

    config.setURLSchemeHandler(chunkLoader, forURLScheme: EditorChunkLoader.scheme)
    config.setURLSchemeHandler(imageLoader, forURLScheme: EditorImageLoader.scheme)

    // Respect user settings for Writing Tools behavior
    if #available(macOS 15.1, *), let writingToolsBehavior = AppRuntimeConfig.writingToolsBehavior {
      config.writingToolsBehavior = writingToolsBehavior
    }

    let webView = EditorWebView(frame: .zero, configuration: config)
    webView.isInspectable = true
    webView.allowsMagnification = true
    webView.uiDelegate = self
    webView.actionDelegate = self

    let theme = AppTheme.current.editorTheme
    DispatchQueue.global(qos: .userInitiated).async {
      let html = [
        AppPreferences.editorConfig(theme: theme).toHtml,
        AppCustomization.editorStyle.fileContents,
        AppCustomization.stylesDirectory.directoryContents.joined(separator: "\n"),
      ].joined(separator: "\n\n")

      DispatchQueue.main.async {
        // Non-nil baseURL is required by scenarios like opening local files
        webView.loadHTMLString(
          html.replacingOccurrences(of: "\"{{USER_SETTINGS}}\"", with: AppRuntimeConfig.jsonLiteral),
          baseURL: EditorWebView.baseURL
        )
      }
    }

    // [macOS 15] Detect Writing Tools visibility to work around issues
    if #available(macOS 15.1, *) {
      writingToolsObservation = webView.observe(\.isWritingToolsActive) { [weak self] _, _ in
        guard let self else {
          return
        }

        self.updateWritingTools(isActive: self.webView.isWritingToolsActive)
      }
    }

    return webView
  }()

  private(set) lazy var completionContext = {
    TextCompletionContext(
      modernStyle: AppDesign.modernStyle,
      effectViewType: AppDesign.modernEffectView,
      localizable: TextCompletionLocalizable(selectedHint: Localized.General.selected)
    ) { [weak self] in
      guard let self else {
        return
      }

      Task { @MainActor in
        self.commitCompletion()
      }
    }
  }()

  // For CoreEditor preload
  private var loadingContinuations = [CheckedContinuation<Void, Never>]()

  deinit {
    if let monitor = localEventMonitor { NSEvent.removeMonitor(monitor) }
    if let monitor = commandBarEventMonitor { NSEvent.removeMonitor(monitor) }
    noteAutosaveTimer?.invalidate()
  }

  init(preloadDelay: TimeInterval? = nil) {
    super.init(nibName: nil, bundle: nil)

    if let preloadDelay, preloadDelay > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + preloadDelay) { [weak self] in
        _ = self?.webView
      }
    } else {
      _ = self.webView
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    setUp()
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    configureToolbar()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    guard !hasUnfinishedAnimations else {
      return
    }

    layoutPanels()
    layoutWebView()
    layoutStatusView()
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    handleMouseMoved(event)
  }

  override func complete(_ sender: Any?) {
    if completionContext.isPanelVisible {
      cancelCompletion()
    } else {
      bridge.completion.startCompletion(afterDelay: 0)
    }
  }

  override func cancelOperation(_ sender: Any?) {
    if isFindPanelFirstResponder {
      updateTextFinderMode(.hidden)
    }

    if webView.isFirstResponder {
      removeFloatingUIElements()
    }

    removePresentedPopovers(contentClass: StatisticsController.self)
  }

  override var representedObject: Any? {
    didSet {
      // If there's a file on disk, its data must be in memory
      guard document?.isContentReady == true else {
        return
      }

      resetEditor()
    }
  }
}

// MARK: - Exposed Methods

extension EditorViewController {
  func waitUntilLoaded() async {
    if hasFinishedLoading {
      return
    }

    await withCheckedContinuation {
      loadingContinuations.append($0)
    }
  }

  func prepareInitialContent(_ text: String) {
    if hasFinishedLoading {
      prependTextContent(text)
    } else {
      initialContent = text
    }
  }

  func prependTextContent(_ text: String) {
    bridge.core.insertText(text: text, from: 0, to: 0)
  }

  func resetEditor() {
    guard hasFinishedLoading, let textContent = document?.stringValue else {
      return
    }

    let selectionRange: SelectionRange? = {
      guard AppRuntimeConfig.restoreLastSelection, let fileURL = document?.fileURL else {
        return nil
      }

      // Content was reloaded from disk due to an external edit, discard stale offsets
      if document?.hasBeenReverted == true {
        EditorSelectionHistory.discard(for: fileURL)
        return nil
      }

      // Non-LF files have mismatched lengths due to CodeMirror normalization, skip the check
      let fileSize = textContent.contains("\r") ? nil : textContent.utf16.count
      return EditorSelectionHistory.selectionRange(for: fileURL, fileSize: fileSize)
    }()

    bridge.core.resetEditor(text: textContent, selectionRange: selectionRange) { [weak self] _ in
      self?.webView.magnification = 1.0

      // Initial content from scenarios like "CreateNewDocumentIntent" or "New File from Clipboard"
      if let text = self?.initialContent {
        self?.prependTextContent(text)
        self?.initialContent = nil
      }
    }

    hasBeenEdited = false
    setShowSelectionStatus(enabled: AppPreferences.Editor.showSelectionStatus)
  }

  func setHasModalSheet(value: Bool) {
    bridge.core.setHasModalSheet(value: value)
  }

  func handleFileURLChange() {
    guard hasBeenEdited else {
      return
    }

    bridge.history.markContentClean()
  }

  func ensureWritingToolsSelectionRect() {
    bridge.writingTools.ensureSelectionRect()
  }
}
