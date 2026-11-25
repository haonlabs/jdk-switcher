// Menu bar UI and CLI. No arguments starts the menu bar app.
import ServiceManagement
import SwiftUI

final class Model: ObservableObject {
    @Published var jdks: [JDK] = []
    @Published var current: String?
    @Published var launchAtLogin = false

    init() {
        reload()
        setLaunchdJavaHome(current)  // launchctl env is lost on reboot
    }

    func reload() {
        jdks = detectJDKs()
        current = currentJDKDir()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Header line in the menu, e.g. "Active: JDK 17.0.21 — Homebrew".
    var activeLabel: String {
        guard let c = current else { return "Active: Default (Android Studio)" }
        return jdks.first { $0.home == c }.map { "Active: JDK \($0.version) — \($0.source)" } ?? "Active: \(c)"
    }

    func pick(_ path: String?) {
        do { try applyJDK(path) } catch { show(error) }
        reload()
    }

    func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { show(error) }
        reload()
    }

    private func show(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        NSAlert(error: error).runModal()
    }
}

struct JDKSwitcherApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            Text(model.activeLabel)
            Divider()
            Toggle("Default (Android Studio)", isOn: binding(nil))
            ForEach(model.jdks, id: \.self) { jdk in
                Toggle("JDK \(jdk.version) — \(jdk.source)", isOn: binding(jdk.home))
            }
            if let c = model.current, !model.jdks.contains(where: { $0.home == c }) {
                Toggle("Custom: \(c)", isOn: .constant(true))
            }
            Divider()
            Button("Refresh") { model.reload() }.keyboardShortcut("r")
            Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: { _ in model.toggleLogin() }))
            Button("About JDK Switcher") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Divider()
            Button("Quit JDK Switcher") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: menuIcon).accessibilityLabel(model.activeLabel)
        }
    }

    private func binding(_ path: String?) -> Binding<Bool> {
        Binding(get: { model.current == path }, set: { _ in model.pick(path) })
    }
}

/// Menu bar logo, drawn by Sources/Logo.swift.
/// Template image, so it follows the menu bar's light/dark look.
let menuIcon: NSImage = {
    let img = NSImage(size: NSSize(width: 23, height: 16), flipped: false) { _ in drawLogo(); return true }
    img.isTemplate = true
    return img
}()

let usage = """
usage: JDKSwitcher                 start the menu bar app
       JDKSwitcher --list          show detected JDKs and the current one
       JDKSwitcher --set <major|path|default>
"""

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "--list":
    print("current: \(currentJDKDir() ?? "default (Android Studio)")")
    for j in detectJDKs() { print("\(j.version)\t\(j.source)\t\(j.home)") }
case "--set" where args.count == 2:
    let want = args[1]
    let path: String? = want == "default" ? nil
        : want.hasPrefix("/") ? want
        : detectJDKs().first { $0.major == want }?.home
    if want != "default" && (path == nil || javaVersion(path!) == nil) { print("no JDK \(want) found"); exit(1) }
    do { try applyJDK(path) } catch { print(error.localizedDescription); exit(1) }
    print("jdk-dir = \(path ?? "default")")
case "--help", "-h":
    print(usage)
default:
    JDKSwitcherApp.main()
}
