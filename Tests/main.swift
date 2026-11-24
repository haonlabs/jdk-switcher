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

print(failed == 0 ? "selftest: passed" : "selftest: \(failed) failed")
exit(failed == 0 ? 0 : 1)
