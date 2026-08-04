// App/StatusBarController.swift
//
// A hand-built AppKit NSStatusItem replacement for the unreliable SwiftUI MenuBarExtra.
// Provides direct click handling:
//   - LEFT-CLICK: opens the dashboard window
//   - RIGHT-CLICK: shows the context menu
//
// Icon mapping is ported from MenuBarLabel.presentation(for:), with template
// rendering for idle (system auto-inverting) and tinted rendering for active states.
//
// The right-click menu replicates SpeakMenu's structure using NSMenuItem.

import AppKit
import Observation
import SpeakCore

// MARK: - StatusBarController

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let controller: DictationController
    private var iconObserverTask: Task<Void, Never>?

    /// AVB-7 (specs/avb7-durable-calls-design.md): count of non-terminal
    /// `AgentCall`s, polled on a coarse timer (matches the inbox pane's own
    /// polling — no push-style live updates in this slice). Drives a small
    /// badge overlay on the menubar icon. [decision: AVB-7]
    private var agentInboxCount: Int = 0
    private var agentInboxPollTask: Task<Void, Never>?

    init(controller: DictationController) {
        self.controller = controller

        // Create the status item with variable length to fit the icon.
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        // Configure the button and menu.
        configureButton()
        updateIcon()

        // Start observing icon changes.
        startObservingIcon()
        startPollingAgentInbox()
    }

    deinit {
        agentInboxPollTask?.cancel()
        iconObserverTask?.cancel()
    }

    /// Poll `agentCallStore.pendingAndPresented().count` on a coarse interval
    /// and redraw the badge on change. [decision: AVB-7]
    private func startPollingAgentInbox() {
        agentInboxPollTask?.cancel()
        agentInboxPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let count = (try? await self.controller.agentCallStore.pendingAndPresented().count) ?? 0
                if count != self.agentInboxCount {
                    self.agentInboxCount = count
                    self.updateIcon()
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    /// Configure the status item button for click handling.
    private func configureButton() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Update the icon based on the current controller state.
    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let (symbolName, color, isTemplate) = iconPresentation(for: controller.icon)

        var image: NSImage?
        if isTemplate {
            // Idle state: use template rendering (auto-inverting on the menubar).
            image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            image?.isTemplate = true
        } else {
            // Active states: use tinted rendering.
            if let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                image = tintImage(baseImage, with: color)
                image?.isTemplate = false
            }
        }

        if agentInboxCount > 0, let image {
            // AVB-7: overlay a small count badge. Plain styling — FE-3 will
            // restyle once the design-token system lands. [decision: AVB-7]
            button.image = badgedImage(image, count: agentInboxCount)
        } else {
            button.image = image
        }
    }

    /// Draw a small red count badge in the top-right corner of `base`.
    /// [decision: AVB-7 — plain styling, FE-3 restyles later]
    private func badgedImage(_ base: NSImage, count: Int) -> NSImage {
        let size = base.size
        let result = NSImage(size: size)
        result.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))

        let badgeDiameter: CGFloat = max(size.width, size.height) * 0.55
        let badgeOrigin = NSPoint(x: size.width - badgeDiameter * 0.7, y: size.height - badgeDiameter * 0.7)
        let badgeRect = NSRect(x: badgeOrigin.x, y: badgeOrigin.y, width: badgeDiameter, height: badgeDiameter)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        let label = count > 9 ? "9+" : "\(count)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: badgeDiameter * 0.62, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let labelSize = label.size(withAttributes: attributes)
        let labelOrigin = NSPoint(
            x: badgeRect.midX - labelSize.width / 2,
            y: badgeRect.midY - labelSize.height / 2
        )
        label.draw(at: labelOrigin, withAttributes: attributes)

        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    /// Tint an NSImage with the specified color.
    private func tintImage(_ image: NSImage, with color: NSColor) -> NSImage {
        guard let tintedImage = image.copy() as? NSImage else {
            return image
        }
        tintedImage.lockFocus()
        color.set()
        let bounds = NSRect(origin: .zero, size: tintedImage.size)
        bounds.fill(using: .sourceAtop)
        tintedImage.unlockFocus()
        return tintedImage
    }

    /// Returns (SF Symbol name, tint color, isTemplate) for each icon state.
    /// When isTemplate is true, the icon uses template rendering (system auto-invert).
    /// When isTemplate is false, the icon is pre-tinted and should not be auto-inverted.
    private func iconPresentation(for icon: MenubarIcon) -> (String, NSColor, Bool) {
        switch icon {
        case .idle:
            // Template rendering (auto-inverting) with secondary label color.
            return ("waveform", NSColor.secondaryLabelColor, true)

        case .listening:
            // Tinted (non-template) — backs Color.speakStateListening (.systemRed).
            return ("waveform.circle.fill", .systemRed, false)

        case .processing:
            // Tinted (non-template) — backs Color.speakStateProcessing (.systemYellow).
            return ("hourglass", .systemYellow, false)

        case .done:
            // Tinted (non-template) — backs Color.speakStateDone (.systemGreen).
            return ("checkmark.circle", .systemGreen, false)

        case .error:
            // Tinted (non-template) — backs Color.speakStateError (.systemRed).
            return ("xmark.circle", .systemRed, false)
        }
    }

    /// Start observing icon changes and re-arming the observer loop.
    /// Uses withObservationTracking (from @Observable) to react to controller.icon mutations.
    private func startObservingIcon() {
        iconObserverTask?.cancel()
        let task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.controller.icon
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else { break }
                self.updateIcon()
            }
        }
        iconObserverTask = task
    }

    /// Handle left/right click events on the status item button.
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        // Determine if this is a right-click or control-click.
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            // Left-click: open dashboard.
            controller.showDashboard()
        }
    }

    /// Show the context menu.
    private func showMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Build the NSMenu with menu items replicated from SpeakMenu.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Status line (disabled item).
        let statusLine = NSMenuItem()
        statusLine.title = statusLineText(for: controller.icon)
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        // Grant Accessibility Permission (if needed).
        if controller.permissionsNeeded {
            menu.addItem(NSMenuItem.separator())
            let permItem = NSMenuItem()
            permItem.title = "Grant Accessibility Permission"
            permItem.target = self
            permItem.action = #selector(openAccessibilitySettings)
            menu.addItem(permItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Mute/Unmute.
        let muteItem = NSMenuItem()
        muteItem.title = controller.isMuted ? "Unmute Microphone" : "Mute Microphone"
        muteItem.target = self
        muteItem.action = #selector(handleMuteToggle)
        menu.addItem(muteItem)

        if controller.isMuted {
            let muteStatusItem = NSMenuItem()
            muteStatusItem.title = "Muted — dictation disabled"
            muteStatusItem.isEnabled = false
            menu.addItem(muteStatusItem)
        }

        // TODO(#1 follow-up): port Style/Language submenus from QuickSettingsMenu.
        // For now, these are skipped as they require NSMenu-based Picker equivalents.

        menu.addItem(NSMenuItem.separator())

        // Open speak.
        let openItem = NSMenuItem()
        openItem.title = "Open speak…"
        openItem.keyEquivalent = "o"
        openItem.target = self
        openItem.action = #selector(handleOpenSpeak)
        menu.addItem(openItem)

        // AI Studio.
        let aiItem = NSMenuItem()
        aiItem.title = "AI Studio…"
        aiItem.target = self
        aiItem.action = #selector(handleOpenAIStudio)
        menu.addItem(aiItem)

        // AVB-7: Agent Inbox. Opens the dashboard; deep-linking straight to the
        // Agent Inbox pane is left for a follow-up (same TODO shape as AI Studio
        // below — `showDashboard()` doesn't yet expose an `initialSection` hook).
        let inboxTitle = agentInboxCount > 0 ? "Agent Inbox (\(agentInboxCount))…" : "Agent Inbox…"
        let inboxItem = NSMenuItem()
        inboxItem.title = inboxTitle
        inboxItem.target = self
        inboxItem.action = #selector(handleOpenSpeak)
        menu.addItem(inboxItem)

        // History.
        let historyItem = NSMenuItem()
        historyItem.title = "History…"
        historyItem.target = self
        historyItem.action = #selector(handleOpenHistory)
        menu.addItem(historyItem)

        // Paste Last Transcript.
        let pasteItem = NSMenuItem()
        pasteItem.title = "Paste Last Transcript"
        pasteItem.keyEquivalent = "v"
        pasteItem.keyEquivalentModifierMask = [.command, .control]
        pasteItem.isEnabled = !controller.lastTranscript.isEmpty
        pasteItem.target = self
        pasteItem.action = #selector(handlePasteLast)
        menu.addItem(pasteItem)

        // Settings.
        let settingsItem = NSMenuItem()
        settingsItem.title = "Settings…"
        settingsItem.keyEquivalent = ","
        settingsItem.target = self
        settingsItem.action = #selector(handleOpenSettings)
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // About.
        let aboutItem = NSMenuItem()
        aboutItem.title = "About speak…"
        aboutItem.target = self
        aboutItem.action = #selector(handleAbout)
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Quit.
        let quitItem = NSMenuItem()
        quitItem.title = "Quit speak"
        quitItem.keyEquivalent = "q"
        quitItem.target = self
        quitItem.action = #selector(handleQuit)
        menu.addItem(quitItem)

        return menu
    }

    /// Return the status line text for the current icon state.
    private func statusLineText(for icon: MenubarIcon) -> String {
        switch icon {
        case .idle:       return "speak — ready (double-tap Fn to start)"
        case .listening:  return "speak — listening…"
        case .processing: return "speak — processing…"
        case .done:       return "speak — done"
        case .error:      return "speak — error (try again)"
        }
    }

    // MARK: - Menu actions

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func handleMuteToggle() {
        controller.toggleMute()
    }

    @objc private func handleOpenSpeak() {
        controller.showDashboard()
    }

    @objc private func handleOpenAIStudio() {
        controller.showDashboard()
        // TODO(PE-2): deep-link to .aiStudio section when showDashboard() exposes initialSection
    }

    @objc private func handleOpenHistory() {
        controller.showHistory()
    }

    @objc private func handlePasteLast() {
        controller.pasteLastTranscript()
    }

    @objc private func handleOpenSettings() {
        // Open the dedicated Settings window directly. The SwiftUI `showPreferencesWindow:`
        // selector is intentionally NOT used — with the MenuBarExtra removed it is
        // unreliable, and calling both opened two Settings windows.
        controller.showSettings()
    }

    @objc private func handleAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}
