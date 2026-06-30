//  BrowserPanelController.swift
//  An integrated browser pane (spec §12): a dark toolbar with back/forward/reload,
//  an editable URL field, and a close button, over a WKWebView that loads the
//  session's browserURL. Models cmux's preview panel.

import AppKit
import WebKit

final class BrowserPanelController: NSViewController, WKNavigationDelegate, NSTextFieldDelegate {

    /// The session this browser is bound to (we mutate its browserURL through AppState).
    private let sessionID: String
    /// The URL string the panel was created with (used for the initial load).
    private let initialURL: String

    private var webView: WKWebView!
    private var urlField: NSTextField!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var reloadButton: NSButton!

    // MARK: - Init

    init(session: Session) {
        self.sessionID = session.id
        self.initialURL = session.browserURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    // MARK: - View

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.chromeBg.cgColor
        self.view = root

        // --- Toolbar (dark, panelBg) ---
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = Theme.panelBg.cgColor
        root.addSubview(toolbar)

        // Bottom hairline separating the toolbar from the web content.
        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = Theme.border.cgColor
        toolbar.addSubview(separator)

        backButton = makeToolButton(symbol: "chevron.left", fallback: "‹", action: #selector(goBack))
        forwardButton = makeToolButton(symbol: "chevron.right", fallback: "›", action: #selector(goForward))
        reloadButton = makeToolButton(symbol: "arrow.clockwise", fallback: "⟳", action: #selector(reload))
        let closeButton = makeToolButton(symbol: "xmark", fallback: "✕", action: #selector(closeBrowser))

        urlField = NSTextField()
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.stringValue = initialURL
        urlField.font = Theme.monoSmall
        urlField.textColor = Theme.text
        urlField.backgroundColor = Theme.chromeBg
        urlField.drawsBackground = true
        urlField.isBordered = false
        urlField.bezelStyle = .roundedBezel
        urlField.focusRingType = .none
        urlField.lineBreakMode = .byTruncatingTail
        urlField.cell?.usesSingleLineMode = true
        urlField.cell?.wraps = false
        urlField.cell?.isScrollable = true
        urlField.placeholderString = "Enter URL"
        urlField.target = self
        urlField.action = #selector(urlSubmitted)
        urlField.delegate = self
        urlField.wantsLayer = true
        urlField.layer?.cornerRadius = 5
        urlField.layer?.borderWidth = 1
        urlField.layer?.borderColor = Theme.border.cgColor
        toolbar.addSubview(urlField)

        let nav = NSStackView(views: [backButton, forwardButton, reloadButton])
        nav.translatesAutoresizingMaskIntoConstraints = false
        nav.orientation = .horizontal
        nav.spacing = 2
        toolbar.addSubview(nav)
        toolbar.addSubview(closeButton)

        // --- Web view ---
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.wantsLayer = true
        webView.layer?.backgroundColor = Theme.terminalBg.cgColor
        root.addSubview(webView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 38),

            separator.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            nav.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            nav.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            urlField.leadingAnchor.constraint(equalTo: nav.trailingAnchor, constant: 8),
            urlField.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            urlField.heightAnchor.constraint(equalToConstant: 24),

            closeButton.leadingAnchor.constraint(equalTo: urlField.trailingAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        load(initialURL)
        updateNavButtons()
    }

    // MARK: - Toolbar factory

    private func makeToolButton(symbol: String, fallback: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = Theme.textDim
        button.target = self
        button.action = action
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button.image = img
            button.imageScaling = .scaleProportionallyDown
        } else {
            button.imagePosition = .noImage
            button.title = fallback
            button.font = Theme.mono
            button.contentTintColor = nil
        }
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        return button
    }

    // MARK: - Loading

    /// Normalize a user-entered string into a URL, prefixing http:// when no scheme is present.
    private func normalized(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        return URL(string: withScheme)
    }

    private func load(_ raw: String) {
        guard let url = normalized(raw) else { return }
        webView.load(URLRequest(url: url))
    }

    // MARK: - Actions

    @objc private func urlSubmitted() {
        let value = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        AppState.shared.setBrowserURL(sessionID, value)
        load(value)
        view.window?.makeFirstResponder(webView)
    }

    @objc private func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    @objc private func goForward() {
        if webView.canGoForward { webView.goForward() }
    }

    @objc private func reload() {
        webView.reload()
    }

    @objc private func closeBrowser() {
        AppState.shared.toggleBrowser(sessionID, force: false)
    }

    // MARK: - Helpers

    private func updateNavButtons() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
        backButton.contentTintColor = webView.canGoBack ? Theme.text : Theme.textFaint
        forwardButton.contentTintColor = webView.canGoForward ? Theme.text : Theme.textFaint
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let current = webView.url?.absoluteString, urlField.currentEditor() == nil {
            urlField.stringValue = current
        }
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let current = webView.url?.absoluteString, urlField.currentEditor() == nil {
            urlField.stringValue = current
        }
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateNavButtons()
    }
}
