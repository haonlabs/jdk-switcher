<p align="center">
  <img src="docs/icon.png" width="128" alt="JDK Switcher icon">
</p>

<h1 align="center">JDK Switcher</h1>

<p align="center">
  Switch the JDK for Flutter, Gradle, Android Studio and VS Code from the menu bar, on your Mac only.<br>
  Only local, per-user settings change, so teammates' builds never break.
</p>

<p align="center">
  <a href="https://github.com/haonlabs/jdk-switcher/releases/latest"><b>Download the latest release</b></a>
</p>

---

## Why

Flutter projects don't all build with the same JDK. Older ones on Gradle 7 need JDK 17, newer ones want
21, and Android Studio now bundles JDK 25. The usual fixes are a poor fit:

| Fix | Problem |
|---|---|
| Set `JAVA_HOME` (or use SDKMAN / mise / jenv) | Flutter ignores it. It picks Android Studio's bundled JDK first. |
| Add `org.gradle.java.home=…` to `android/gradle.properties` | It's committed, so a path that only exists on your Mac (e.g. Homebrew) breaks everyone else. |
| Run `flutter config --jdk-dir …` | Works, but you have to remember the full JDK path every time you switch. |

JDK Switcher does the third one for you: pick a JDK in the menu bar, and it sets Flutter's `jdk-dir` in
`~/.config/flutter/settings`. That file is per user, so it applies only to your Mac and to every
Flutter version on it, including ones installed with FVM.

## Features

- Lives in the menu bar as a small cup icon. Click it to see the active JDK.
- One pick switches Flutter (`jdk-dir`), `./gradlew` (`~/.gradle/gradle.properties`), Android Studio's Gradle JDK
  (no restart), VS Code's Java extension (`java.import.gradle.java.home`) and `JAVA_HOME` for other apps.
- Finds JDKs from Android Studio, Homebrew, `/Library/Java/JavaVirtualMachines`, SDKMAN, mise and asdf.
- **Default (Android Studio)** removes the override, so Flutter goes back to its own choice.
- **Launch at Login**, using the native macOS login item API.
- A small CLI for scripts: `--list` and `--set`.
- Never touches tracked source. In projects it only writes gitignored `.gradle/config.properties` (plus a one-time
  Gradle JDK change in `.idea/gradle.xml`).
- Universal binary (Apple Silicon and Intel), macOS 13 Ventura or later.

## Install

1. Download `JDKSwitcher-<version>.dmg` from [Releases](https://github.com/haonlabs/jdk-switcher/releases/latest).
2. Open it and drag **JDK Switcher** into **Applications**.
3. Launch it from Applications. The cup icon appears in the menu bar.

### "JDK Switcher can't be opened" / "Apple could not verify…"

Release builds aren't notarized by Apple yet, so Gatekeeper blocks the first launch. Allow it once, either:

- Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to JDK Switcher, or
- run this in Terminal:

  ```sh
  xattr -dr com.apple.quarantine "/Applications/JDK Switcher.app"
  ```

Prefer not to trust a binary? [Build it yourself](#build-from-source). It takes about a minute.

## Usage

Click the cup icon in the menu bar. The first line shows the active JDK.

| Item | What it does |
|---|---|
| **Default (Android Studio)** | Remove every override. Each tool goes back to its own default. |
| **JDK 17.0.21 — Homebrew**, … | Use this JDK everywhere. The checkmark shows the active one. |
| **Refresh** ⌘R | Rescan after installing or removing a JDK |
| **Launch at Login** | Start JDK Switcher when you log in |
| **Quit JDK Switcher** ⌘Q | Quit. The selected JDK stays active. |

Then build as usual (`flutter run`, `fvm flutter build apk`, VS Code). Check with `flutter doctor -v`,
which prints the Java binary and version under *Android toolchain*.

### Command line

```sh
JS="/Applications/JDK Switcher.app/Contents/MacOS/JDKSwitcher"
"$JS" --list          # detected JDKs and the current one
"$JS" --set 17        # by major version
"$JS" --set /path/to/jdk/Contents/Home
"$JS" --set default   # back to Android Studio's JDK
```

## How it works

Flutter picks the JDK for Android builds in this order:

1. `jdk-dir` from `flutter config` (stored in `~/.config/flutter/settings`)
2. The JDK bundled with Android Studio
3. `JAVA_HOME`
4. `java` on your `PATH`

Picking a JDK writes it to every place that chooses one:

| Where | Used by | Takes effect |
|---|---|---|
| `jdk-dir` in `~/.config/flutter/settings` | `flutter` CLI, VS Code and Android Studio Flutter builds | immediately |
| `org.gradle.java.home` in `~/.gradle/gradle.properties` | every `./gradlew` run (native Android, Flutter's Gradle) | immediately |
| `java.home` in `<gradle root>/.gradle/config.properties` of every project in Android Studio's recent list | Android Studio, with Gradle JDK set to `#GRADLE_LOCAL_JAVA_HOME` | next Gradle sync |
| `JAVA_HOME` via `launchctl setenv` | apps opened afterwards: VS Code, Terminal | after restarting the app |
| `java.import.gradle.java.home` in VS Code / Cursor / VSCodium / Windsurf `settings.json` | VS Code's Java and Gradle extensions (Kotlin/Java in `android/`) | immediately |

For Android Studio, `.gradle/` is gitignored by default. The first time a project is switched, its
`.idea/gradle.xml` Gradle JDK changes to `#GRADLE_LOCAL_JAVA_HOME`, the portable value Android Studio itself
uses for new projects. If that file is committed, you'll see that one-line diff once. **Default (Android Studio)**
writes Android Studio's bundled JDK there.

Each edit only touches its own key and keeps your comments and other settings. If the Flutter settings file
isn't valid JSON, it refuses to write instead of overwriting it. `launchctl` values are lost on reboot, so the
app re-applies the current JDK each time it starts (turn on **Launch at Login**).

The source is a few small files:

```
Sources/main.swift          menu bar UI, Launch at Login, CLI
Sources/JDKStore.swift      JDK discovery, Flutter/Gradle/VS Code settings, JAVA_HOME
Tests/main.swift            self-check for discovery and the settings file
Sources/Logo.swift          the logo, for the menu bar and the app icon
scripts/make-icon/main.swift  draws the app icon
build.sh                    builds the .app and .dmg
```

## Build from source

Requirements: macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't needed.

```sh
git clone https://github.com/haonlabs/jdk-switcher.git
cd jdk-switcher
./build.sh
```

This runs the self-check, compiles a universal binary, draws the icon, signs the app ad hoc, and creates:

- `build/JDK Switcher.app`
- `build/JDKSwitcher-<version>.dmg`

The version comes from `CFBundleShortVersionString` in `Info.plist`.

### Signed and notarized builds

With an Apple Developer account, set these and the build is signed with your Developer ID and the DMG is
notarized and stapled, so users get no Gatekeeper warning:

```sh
xcrun notarytool store-credentials jdk-switcher   # once
SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=jdk-switcher ./build.sh
```

## Troubleshooting

**Android Studio still builds with another JDK / shows red errors.** Click **Sync Project with Gradle Files**.
Only projects in Android Studio's recent list are switched; for a project opened for the first time, open it once,
then click **Refresh** and pick the JDK again.

**VS Code still shows red in `android/`.** Run *Java: Clean Java Language Server Workspace* once after switching.

**My JDK isn't listed.** Click **Refresh**. If it's installed somewhere else, use
`--set /path/to/Home`. The menu shows it as *Custom*.

**Launch at Login doesn't stick.** Make sure the app runs from `/Applications`, and allow it under
System Settings → General → Login Items.

## Known limitations

- The choice is global for your user, not per project. Switch when you move to a project that needs another JDK.
- A shell that exports its own `JAVA_HOME` (e.g. in `~/.zshrc`) overrides the one set by `launchctl`.

## Contributing

Issues and pull requests are welcome. Please keep it small: JDK Switcher aims to stay a few hundred lines
with no dependencies. Run `./build.sh` before opening a PR; it fails if the self-check fails.
When you add a JDK location, add a case to `Tests/main.swift` if it changes how homes are recognized.

## License

[MIT](LICENSE)
