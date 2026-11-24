// JDK discovery and Flutter's "jdk-dir" setting. No UI here, so Tests/main.swift can compile it alone.
import Foundation

struct JDK: Hashable {
    let home: String
    let version: String
    let source: String
    var major: String { String(version.split(separator: ".").first ?? "?") }
}

let fm = FileManager.default
let homeDir = fm.homeDirectoryForCurrentUser.path
/// Same file `flutter config --jdk-dir` writes. Shared by every Flutter version on this machine.
let flutterSettings = URL(fileURLWithPath: homeDir + "/.config/flutter/settings")

/// A JDK home has an executable bin/java and a `release` file with JAVA_VERSION.
func javaVersion(_ home: String) -> String? {
    guard fm.isExecutableFile(atPath: home + "/bin/java"),
          let txt = try? String(contentsOfFile: home + "/release", encoding: .utf8) else { return nil }
    for line in txt.split(separator: "\n") where line.hasPrefix("JAVA_VERSION=") {
        return line.dropFirst("JAVA_VERSION=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
    return nil
}

func children(_ dir: String) -> [String] {
    ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted().map { dir + "/" + $0 }
}

func detectJDKs() -> [JDK] {
    var found: [(home: String, source: String)] = []
    for apps in ["/Applications", homeDir + "/Applications"] {
        for app in children(apps) where app.hasSuffix(".app") && app.contains("Android Studio") {
            found.append((app + "/Contents/jbr/Contents/Home", "Android Studio"))
        }
    }
    for opt in children("/opt/homebrew/opt") + children("/usr/local/opt")
    where (opt as NSString).lastPathComponent.hasPrefix("openjdk") {
        found.append((opt + "/libexec/openjdk.jdk/Contents/Home", "Homebrew"))
    }
    for base in ["/Library/Java/JavaVirtualMachines", homeDir + "/Library/Java/JavaVirtualMachines"] {
        for vm in children(base) { found.append((vm + "/Contents/Home", (vm as NSString).lastPathComponent)) }
    }
    // Version managers: each child is a JDK home, either flat or macOS-style (Contents/Home).
    for (base, source) in [(homeDir + "/.sdkman/candidates/java", "SDKMAN"),
                           (homeDir + "/.local/share/mise/installs/java", "mise"),
                           (homeDir + "/.asdf/installs/java", "asdf")] {
        for dir in children(base) { found += [(dir, source), (dir + "/Contents/Home", source)] }
    }
    var seen = Set<String>()  // symlinks (brew "openjdk" vs "openjdk@25", SDKMAN "current") point at the same JDK
    return found.compactMap { home, source in
        guard let v = javaVersion(home), seen.insert((home as NSString).resolvingSymlinksInPath).inserted else { return nil }
        return JDK(home: home, version: v, source: source)
    }
}

/// Throws on an unreadable file instead of returning [:], so a write never wipes other Flutter settings.
func readSettings(_ url: URL = flutterSettings) throws -> [String: Any] {
    guard fm.fileExists(atPath: url.path) else { return [:] }
    let data = try Data(contentsOf: url)
    if data.isEmpty { return [:] }
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NSError(domain: "JDKSwitcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(url.path) is not a JSON object"])
    }
    return obj
}

func currentJDKDir(_ url: URL = flutterSettings) -> String? { (try? readSettings(url))?["jdk-dir"] as? String }

/// nil removes the key, so Flutter falls back to Android Studio's bundled JDK.
func setJDKDir(_ path: String?, _ url: URL = flutterSettings) throws {
    var s = try readSettings(url)
    if let path { s["jdk-dir"] = path } else { s.removeValue(forKey: "jdk-dir") }
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
}
