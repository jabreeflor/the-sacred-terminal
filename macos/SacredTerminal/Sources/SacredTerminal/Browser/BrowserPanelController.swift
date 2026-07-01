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
        root.layer?.backgroundColor = Theme.panelBg.cgColor   // mock .browser-pane #0e0e11
        root.setAccessibilityIdentifier("browser-panel")
        self.view = root

        // Left seam (mock .browser-pane border-left rgba(255,255,255,.08)).
        let leftSeam = NSView()
        leftSeam.translatesAutoresizingMaskIntoConstraints = false
        leftSeam.wantsLayer = true
        leftSeam.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        root.addSubview(leftSeam)

        // --- Toolbar (mock .browser-toolbar #131316) ---
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = Theme.titlebarBg.cgColor
        toolbar.setAccessibilityIdentifier("browser-toolbar")
        root.addSubview(toolbar)

        // Bottom hairline separating the toolbar from the web content.
        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = Theme.hairlineSoft.cgColor   // #222228
        toolbar.addSubview(separator)

        backButton = makeToolButton(symbol: "chevron.left", fallback: "‹",
                                    label: "Back", identifier: "browser-back",
                                    action: #selector(goBack))
        forwardButton = makeToolButton(symbol: "chevron.right", fallback: "›",
                                       label: "Forward", identifier: "browser-forward",
                                       action: #selector(goForward))
        reloadButton = makeToolButton(symbol: "arrow.clockwise", fallback: "⟳",
                                      label: "Reload", identifier: "browser-reload",
                                      action: #selector(reload))
        let closeButton = makeToolButton(symbol: "xmark", fallback: "✕",
                                         label: "Close browser", identifier: "browser-close",
                                         action: #selector(closeBrowser))

        // URL box: a styled pill (globe + editable field) — mock .browser-url.
        let urlBox = NSView()
        urlBox.translatesAutoresizingMaskIntoConstraints = false
        urlBox.wantsLayer = true
        urlBox.layer?.cornerRadius = 7
        urlBox.layer?.borderWidth = 1
        urlBox.layer?.borderColor = Theme.pickerLine.cgColor       // #2a2a30
        urlBox.layer?.backgroundColor = Theme.browserUrlBg.cgColor // #0d0d10
        urlBox.setAccessibilityIdentifier("browser-url-box")

        let globe = NSImageView()
        globe.translatesAutoresizingMaskIntoConstraints = false
        globe.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        globe.contentTintColor = Theme.textFaint
        globe.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        urlBox.addSubview(globe)

        urlField = NSTextField()
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.stringValue = initialURL
        urlField.font = Theme.monoSmall
        urlField.textColor = Theme.text
        urlField.drawsBackground = false
        urlField.isBordered = false
        urlField.focusRingType = .none
        urlField.lineBreakMode = .byTruncatingTail
        urlField.cell?.usesSingleLineMode = true
        urlField.cell?.wraps = false
        urlField.cell?.isScrollable = true
        urlField.placeholderString = "Enter URL"
        urlField.target = self
        urlField.action = #selector(urlSubmitted)
        urlField.delegate = self
        urlField.setAccessibilityLabel("Browser URL")
        urlField.setAccessibilityIdentifier("browser-url")
        urlBox.addSubview(urlField)
        toolbar.addSubview(urlBox)

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
        webView.layer?.backgroundColor = NSColor.white.cgColor   // mock .browser-frame #fff
        root.addSubview(webView)

        NSLayoutConstraint.activate([
            leftSeam.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            leftSeam.topAnchor.constraint(equalTo: root.topAnchor),
            leftSeam.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            leftSeam.widthAnchor.constraint(equalToConstant: 1),

            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 36),

            separator.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            nav.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            nav.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            urlBox.leadingAnchor.constraint(equalTo: nav.trailingAnchor, constant: 6),
            urlBox.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            urlBox.heightAnchor.constraint(equalToConstant: 28),

            globe.leadingAnchor.constraint(equalTo: urlBox.leadingAnchor, constant: 10),
            globe.centerYAnchor.constraint(equalTo: urlBox.centerYAnchor),
            globe.widthAnchor.constraint(equalToConstant: 12),
            globe.heightAnchor.constraint(equalToConstant: 12),

            urlField.leadingAnchor.constraint(equalTo: globe.trailingAnchor, constant: 6),
            urlField.trailingAnchor.constraint(equalTo: urlBox.trailingAnchor, constant: -8),
            urlField.centerYAnchor.constraint(equalTo: urlBox.centerYAnchor),

            closeButton.leadingAnchor.constraint(equalTo: urlBox.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leftSeam.trailingAnchor),
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

    private func makeToolButton(symbol: String,
                                fallback: String,
                                label: String,
                                identifier: String,
                                action: Selector) -> NSButton {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier(identifier)
        button.contentTintColor = Theme.textDim
        button.target = self
        button.action = action
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
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
            button.heightAnchor.constraint(equalToConstant: 26),
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
