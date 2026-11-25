// Self-check for JDK detection and the settings file, run by build.sh. Works in a temp dir only.
import Foundation

var failed = 0
func check(_ name: String, _ ok: Bool) { if !ok { print("FAIL: \(name)"); failed += 1 } }

let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("jdkswitcher-selftest-\(getpid())")
defer { try? fm.removeItem(at: tmp) }
let home = tmp.appendingPathComponent("jdk").path
try fm.createDirectory(atPath: home + "/bin", withIntermediateDirectories: true)

// javaVersion
check("no release file is not a JDK", javaVersion(home) == nil)
try "IMPLEMENTOR=\"Eclipse Adoptium\"\nJAVA_VERSION=\"17.0.21\"\n".write(toFile: home + "/release", atomically: true, encoding: .utf8)
check("no bin/java is not a JDK", javaVersion(home) == nil)
fm.createFile(atPath: home + "/bin/java", contents: Data(), attributes: [.posixPermissions: 0o755])
check("reads JAVA_VERSION", javaVersion(home) == "17.0.21")
check("major version", JDK(home: home, version: "17.0.21", source: "").major == "17")

// settings file
let settings = tmp.appendingPathComponent("flutter/settings")
check("missing file means default", currentJDKDir(settings) == nil)
try fm.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
try #"{"enable-web": true}"#.write(to: settings, atomically: true, encoding: .utf8)
try setJDKDir(home, settings)
check("set jdk-dir", currentJDKDir(settings) == home)
check("set keeps other settings", (try readSettings(settings))["enable-web"] as? Bool == true)
try setJDKDir(nil, settings)
check("default removes jdk-dir", currentJDKDir(settings) == nil)
check("default keeps other settings", (try readSettings(settings))["enable-web"] as? Bool == true)
try "not json".write(to: settings, atomically: true, encoding: .utf8)
check("refuses to overwrite a broken file", (try? setJDKDir(home, settings)) == nil)
check("broken file left untouched", (try? String(contentsOf: settings, encoding: .utf8)) == "not json")

// ~/.gradle/gradle.properties
let gp = tmp.appendingPathComponent("gradle/gradle.properties")
try setGradleJavaHome("/a", gp)
check("gradle: creates file", (try? String(contentsOf: gp, encoding: .utf8)) == "org.gradle.java.home=/a\n")
try "org.gradle.jvmargs=-Xmx4g\n# org.gradle.java.home=/keep\norg.gradle.java.home=/old\nx=1".write(to: gp, atomically: true, encoding: .utf8)
try setGradleJavaHome("/b", gp)
check("gradle: replaces, keeps rest", (try? String(contentsOf: gp, encoding: .utf8)) == "org.gradle.jvmargs=-Xmx4g\n# org.gradle.java.home=/keep\nx=1\norg.gradle.java.home=/b\n")
try setGradleJavaHome(nil, gp)
check("gradle: default removes", (try? String(contentsOf: gp, encoding: .utf8)) == "org.gradle.jvmargs=-Xmx4g\n# org.gradle.java.home=/keep\nx=1\n")

// VS Code settings.json (JSONC)
let vs = tmp.appendingPathComponent("Code/User/settings.json")
try setVSCodeJavaHome("/a", vs)
check("vscode: skipped when not installed", !fm.fileExists(atPath: vs.path))
try fm.createDirectory(at: vs.deletingLastPathComponent(), withIntermediateDirectories: true)
let jsonc = "{\n  // \"java.import.gradle.java.home\": \"/keep\",\n  \"editor.fontSize\": 14,\n}\n"
try jsonc.write(to: vs, atomically: true, encoding: .utf8)
try setVSCodeJavaHome("/a", vs)
try setVSCodeJavaHome("/b", vs)
check("vscode: sets once, keeps comments", (try? String(contentsOf: vs, encoding: .utf8)) == "{\n  \"java.import.gradle.java.home\": \"/b\",\n  // \"java.import.gradle.java.home\": \"/keep\",\n  \"editor.fontSize\": 14,\n}\n")
try setVSCodeJavaHome(nil, vs)
check("vscode: default restores file", (try? String(contentsOf: vs, encoding: .utf8)) == jsonc)

// Android Studio: recent projects -> .idea/gradle.xml -> <gradle root>/.gradle/config.properties
let gbase = tmp.appendingPathComponent("Google").path
let proj = tmp.appendingPathComponent("proj").path
try fm.createDirectory(atPath: gbase + "/AndroidStudio2026.2/options", withIntermediateDirectories: true)
try fm.createDirectory(atPath: proj + "/.idea", withIntermediateDirectories: true)
try "<entry key=\"\(proj)\"><entry key=\"/nope\">".write(toFile: gbase + "/AndroidStudio2026.2/options/recentProjects.xml", atomically: true, encoding: .utf8)
try """
    <GradleProjectSettings>
      <option name="externalProjectPath" value="$PROJECT_DIR$/android" />
      <option name="gradleJvm" value="homebrew-17" />
    </GradleProjectSettings>
    <GradleProjectSettings>
      <option name="externalProjectPath" value="$PROJECT_DIR$" />
    </GradleProjectSettings>
    """.write(toFile: proj + "/.idea/gradle.xml", atomically: true, encoding: .utf8)
check("studio: finds recent projects", androidStudioGradleXMLs(gbase) == [proj + "/.idea/gradle.xml"])
try fm.createDirectory(atPath: proj + "/.gradle", withIntermediateDirectories: true)
try "# local\njava.home=/old\n".write(toFile: proj + "/.gradle/config.properties", atomically: true, encoding: .utf8)
try setAndroidStudioJavaHome("/b", gradleXML: proj + "/.idea/gradle.xml")
let gx = (try? String(contentsOfFile: proj + "/.idea/gradle.xml", encoding: .utf8)) ?? ""
check("studio: gradleJvm -> local java home", !gx.contains("homebrew-17") && gx.contains(##"<option name="gradleJvm" value="#GRADLE_LOCAL_JAVA_HOME" />"##))
check("studio: android root", (try? String(contentsOfFile: proj + "/android/.gradle/config.properties", encoding: .utf8)) == "java.home=/b\n")
check("studio: project root, keeps rest", (try? String(contentsOfFile: proj + "/.gradle/config.properties", encoding: .utf8)) == "# local\njava.home=/b\n")

print(failed == 0 ? "selftest: passed" : "selftest: \(failed) failed")
exit(failed == 0 ? 0 : 1)
