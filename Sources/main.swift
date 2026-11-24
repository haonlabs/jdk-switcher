// Menu bar UI and CLI. No arguments starts the menu bar app.
import ServiceManagement
import SwiftUI

final class Model: ObservableObject {
    @Published var jdks: [JDK] = []
    @Published var current: String?
    @Published var launchAtLogin = false

    init() { reload() }

    func reload() {
        jdks = detectJDKs()
        current = currentJDKDir()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Menu bar text: "J" + the major version Flutter will use.
    var label: String {
        let active = current.map { c in jdks.first { $0.home == c } } ?? jdks.first { $0.source == "Android Studio" }
        return "J" + (active?.major ?? "?")
    }

    func pick(_ path: String?) {
        do { try setJDKDir(path) } catch { show(error) }
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
            Text("JDK used by Flutter")
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
            Image(nsImage: menuBadge(model.label))
        }
    }

    private func binding(_ path: String?) -> Binding<Bool> {
        Binding(get: { model.current == path }, set: { _ in model.pick(path) })
    }
}

/// Filled rounded badge with the text knocked out. Template image, so it follows the menu bar's light/dark look.
func menuBadge(_ text: String) -> NSImage {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .heavy)]
    let ts = (text as NSString).size(withAttributes: attrs)
    let img = NSImage(size: NSSize(width: ceil(ts.width) + 10, height: 16), flipped: false) { r in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        (text as NSString).draw(at: NSPoint(x: (r.width - ts.width) / 2, y: (r.height - ts.height) / 2), withAttributes: attrs)
        return true
    }
    img.isTemplate = true
    return img
}

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
    do { try setJDKDir(path) } catch { print(error.localizedDescription); exit(1) }
    print("jdk-dir = \(path ?? "default")")
case "--help", "-h":
    print(usage)
default:
    JDKSwitcherApp.main()
}
