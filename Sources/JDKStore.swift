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

// MARK: - Everything else that picks a JDK: Gradle CLI, GUI apps (Android Studio, VS Code), VS Code's Java extension.

let gradleProps = URL(fileURLWithPath: homeDir + "/.gradle/gradle.properties")
/// VS Code and its forks. Only ones that are installed (User dir exists) get touched.
let vscodeSettings = ["Code", "Code - Insiders", "Cursor", "VSCodium", "Windsurf"]
    .map { URL(fileURLWithPath: homeDir + "/Library/Application Support/\($0)/User/settings.json") }

/// Removes every non-commented line matching `pattern`, then inserts `line` (if any) via `insert`.
/// Plain text edit so comments and formatting in the user's file survive.
func editLines(_ url: URL, _ pattern: String, _ line: String?, insert: (String, String) -> String) throws {
    let old = fm.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : ""
    let re = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
    var s = re.stringByReplacingMatches(in: old, range: NSRange(old.startIndex..., in: old), withTemplate: "")
    if let line { s = insert(s, line) }
    if s == old { return }
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try s.write(to: url, atomically: true, encoding: .utf8)
}

/// Sets (or with nil removes) one `key=value` line in a .properties file.
func setProperty(_ key: String, _ value: String?, _ url: URL) throws {
    try editLines(url, "^[ \\t]*" + NSRegularExpression.escapedPattern(for: key) + "[ \\t]*[=:].*\\n?",
                  value.map { key + "=" + $0.replacingOccurrences(of: "\\", with: "\\\\") }) { s, l in
        (s.isEmpty || s.hasSuffix("\n") ? s : s + "\n") + l + "\n"
    }
}

/// `org.gradle.java.home` beats JAVA_HOME for every `./gradlew` run on this Mac, effective immediately.
func setGradleJavaHome(_ path: String?, _ url: URL = gradleProps) throws {
    try setProperty("org.gradle.java.home", path, url)
}

/// VS Code settings are JSONC (comments, trailing commas), so this edits text instead of parsing.
func setVSCodeJavaHome(_ path: String?, _ url: URL) throws {
    guard fm.fileExists(atPath: url.deletingLastPathComponent().path) else { return }
    let esc = path.map { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
    try editLines(url, #"^[ \t]*"java\.import\.gradle\.java\.home"[ \t]*:[ \t]*"(?:[^"\\\n]|\\.)*"[ \t]*,?[ \t]*\n?"#,
                  esc.map { "  \"java.import.gradle.java.home\": \"\($0)\"," }) { s, l in
        guard let brace = s.firstIndex(of: "{") else { return "{\n\(l)\n}\n" }
        return String(s[...brace]) + "\n" + l + String(s[s.index(after: brace)...])
    }
}

/// JAVA_HOME for apps launched from now on (Android Studio's "JAVA_HOME" Gradle JDK, VS Code). Lost on reboot,
/// so the menu bar app re-applies it at launch.
func setLaunchdJavaHome(_ path: String?) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = path.map { ["setenv", "JAVA_HOME", $0] } ?? ["unsetenv", "JAVA_HOME"]
    try? p.run()
    p.waitUntilExit()
}

// MARK: - Android Studio. Gradle JDK "#GRADLE_LOCAL_JAVA_HOME" reads java.home from <gradle root>/.gradle/config.properties
// (gitignored) at every sync, so switching needs no restart.

func firstGroups(_ pattern: String, _ s: String) -> [String] {
    let re = try! NSRegularExpression(pattern: pattern)
    return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range(at: 1), in: s).map { String(s[$0]) } }
}

/// .idea/gradle.xml of every project in Android Studio's recent list (all installed versions).
func androidStudioGradleXMLs(_ base: String = homeDir + "/Library/Application Support/Google") -> [String] {
    let projects = children(base).filter { ($0 as NSString).lastPathComponent.hasPrefix("AndroidStudio") }
        .compactMap { try? String(contentsOfFile: $0 + "/options/recentProjects.xml", encoding: .utf8) }
        .flatMap { firstGroups(#"<entry key="([^"]+)""#, $0) }
        .map { $0.replacingOccurrences(of: "$USER_HOME$", with: homeDir) + "/.idea/gradle.xml" }
    return Array(Set(projects)).sorted().filter { fm.fileExists(atPath: $0) }
}

/// Points the project's Gradle JDK at #GRADLE_LOCAL_JAVA_HOME (once) and writes `path` as each Gradle root's java.home.
func setAndroidStudioJavaHome(_ path: String?, gradleXML: String) throws {
    let projectDir = ((gradleXML as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
    let old = try String(contentsOfFile: gradleXML, encoding: .utf8)
    var xml = old.replacingOccurrences(of: #"(<option name="gradleJvm" value=")[^"]*""#,
                                       with: "$1#GRADLE_LOCAL_JAVA_HOME\"", options: .regularExpression)
    // ponytail: only checks the whole file; a multi-root file where just some roots omit gradleJvm keeps those as is.
    if !xml.contains(#"name="gradleJvm""#) {  // option omitted: add it next to each Gradle root
        xml = xml.replacingOccurrences(of: #"([ \t]*)(<option name="externalProjectPath" value="[^"]*" />)"#,
                                       with: "$1$2\n$1<option name=\"gradleJvm\" value=\"#GRADLE_LOCAL_JAVA_HOME\" />",
                                       options: .regularExpression)
    }
    if xml != old { try xml.write(toFile: gradleXML, atomically: true, encoding: .utf8) }
    for root in firstGroups(#"<option name="externalProjectPath" value="([^"]*)""#, xml) {
        let dir = root.replacingOccurrences(of: "$PROJECT_DIR$", with: projectDir)
        try setProperty("java.home", path, URL(fileURLWithPath: dir + "/.gradle/config.properties"))
    }
}

/// Points Flutter, Gradle, Android Studio, GUI apps and VS Code at one JDK. nil = back to each tool's default.
func applyJDK(_ path: String?) throws {
    try setJDKDir(path)
    try setGradleJavaHome(path)
    // Android Studio has no "unset": default means its own bundled JDK.
    let studio = path ?? detectJDKs().first { $0.source == "Android Studio" }?.home
    for xml in androidStudioGradleXMLs() { try setAndroidStudioJavaHome(studio, gradleXML: xml) }
    for url in vscodeSettings { try setVSCodeJavaHome(path, url) }
    setLaunchdJavaHome(path)
}
