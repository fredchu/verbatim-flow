# On-Demand Python venv Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** App 啟動時自動在 `~/Library/Application Support/VerbatimFlow/` 建立 Python venv 並安裝依賴，讓從 /Applications/ 安裝的使用者不需手動設定。

**Architecture:** 新增 `PythonEnvironmentManager` 負責 venv 生命週期（偵測、建立、hash 比對）。修改 `PythonScriptRunner` 加入 Application Support 路徑候選。修改 `MenuBarApp` 在 `applicationDidFinishLaunching` 觸發背景 setup。修改 build script 打包 `requirements.txt`。

**Tech Stack:** Swift (Foundation, UserNotifications), shell subprocess (python3 -m venv, pip install)

---

### Task 1: Build script — 打包 requirements.txt

**Files:**
- Modify: `scripts/build-native-app.sh:54-64`
- Verify: `apps/mac-client/python/requirements.txt`

**Step 1: 修改 build script**

在 `build-native-app.sh` 中，ditto python scripts 之後加入 requirements.txt 複製：

```bash
# 在 ditto "$PYTHON_SCRIPTS_DIR" 那段之後加入：
# Bundle requirements.txt for on-demand venv setup
if [[ -f "$NATIVE_DIR/python/requirements.txt" ]]; then
  cp "$NATIVE_DIR/python/requirements.txt" "$SIGNING_APP_BUNDLE/Contents/Resources/python/requirements.txt"
fi
```

**Step 2: 驗證**

```bash
cd /Users/fredchu/dev/verbatim-flow && bash scripts/build-native-app.sh
ls -la apps/mac-client/dist/VerbatimFlow.app/Contents/Resources/python/requirements.txt
```

Expected: 檔案存在，內容與 `apps/mac-client/python/requirements.txt` 一致。

**Step 3: Commit**

```bash
git add scripts/build-native-app.sh
git commit -m "build: bundle requirements.txt into app Resources"
```

---

### Task 2: PythonEnvironmentManager — 核心邏輯

**Files:**
- Create: `apps/mac-client/Sources/VerbatimFlow/PythonEnvironmentManager.swift`

**Step 1: 建立 PythonEnvironmentManager**

```swift
import Foundation
import os.log

enum PythonEnvStatus: Sendable {
    case ready
    case setting(String)   // 進度訊息
    case failed(String)    // 錯誤訊息
    case noPython          // 系統找不到 python3
}

enum PythonEnvironmentManager {
    private static let logger = Logger(subsystem: "com.verbatimflow.app", category: "PythonEnv")

    static var appSupportVenvDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VerbatimFlow/.venv")
    }

    static var appSupportPythonURL: URL {
        appSupportVenvDir.appendingPathComponent("bin/python")
    }

    private static let hashFileName = ".requirements_hash"

    /// 找系統 Python，按序: /usr/bin/python3 → homebrew arm64 → homebrew intel
    static func findSystemPython() -> URL? {
        let candidates = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3"
        ]
        let fm = FileManager.default
        for path in candidates {
            if fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// 從 bundle Resources 找 requirements.txt
    static func bundledRequirementsURL() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("python/requirements.txt")
    }

    /// 計算檔案的 SHA256 hex string
    private static func sha256Hex(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// 讀取已存的 hash
    private static func storedHash() -> String? {
        let hashFile = appSupportVenvDir.deletingLastPathComponent().appendingPathComponent(hashFileName)
        return try? String(contentsOf: hashFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 寫入 hash
    private static func writeHash(_ hash: String) {
        let hashFile = appSupportVenvDir.deletingLastPathComponent().appendingPathComponent(hashFileName)
        try? hash.write(to: hashFile, atomically: true, encoding: .utf8)
    }

    /// 檢查 venv 是否就緒且 hash 一致
    static func isReady() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: appSupportPythonURL.path) else { return false }
        guard let reqURL = bundledRequirementsURL(),
              let currentHash = sha256Hex(of: reqURL),
              let stored = storedHash() else {
            return false
        }
        return currentHash == stored
    }

    /// 主入口：背景檢查並建立 venv。透過 callback 回報狀態。
    static func ensureReady(onStatus: @escaping @Sendable (PythonEnvStatus) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            if isReady() {
                logger.info("Python venv is ready")
                onStatus(.ready)
                return
            }

            guard let systemPython = findSystemPython() else {
                logger.error("No system Python found")
                onStatus(.noPython)
                return
            }

            guard let reqURL = bundledRequirementsURL(),
                  FileManager.default.fileExists(atPath: reqURL.path) else {
                logger.error("Bundled requirements.txt not found")
                onStatus(.failed("requirements.txt not found in app bundle"))
                return
            }

            let venvParent = appSupportVenvDir.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: venvParent, withIntermediateDirectories: true)
            } catch {
                onStatus(.failed("Cannot create directory: \(error.localizedDescription)"))
                return
            }

            // Step 1: Create venv
            onStatus(.setting("Creating Python environment..."))
            logger.info("Creating venv at \(appSupportVenvDir.path)")
            let venvResult = runProcess(systemPython.path, args: ["-m", "venv", appSupportVenvDir.path])
            if venvResult.exitCode != 0 {
                onStatus(.failed("Failed to create venv: \(venvResult.stderr)"))
                return
            }

            // Step 2: pip install
            onStatus(.setting("Installing Python packages (this may take a few minutes)..."))
            let pipPath = appSupportVenvDir.appendingPathComponent("bin/pip").path
            let installResult = runProcess(pipPath, args: ["install", "-r", reqURL.path])
            if installResult.exitCode != 0 {
                onStatus(.failed("pip install failed: \(installResult.stderr)"))
                return
            }

            // Step 3: Write hash
            if let hash = sha256Hex(of: reqURL) {
                writeHash(hash)
            }

            logger.info("Python venv setup complete")
            onStatus(.ready)
        }
    }

    private static func runProcess(_ executable: String, args: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe
        // Clean environment to avoid inheriting Claude Code vars etc.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "VIRTUAL_ENV")
        env.removeValue(forKey: "PYTHONHOME")
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, "", error.localizedDescription)
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
```

注意：`CC_SHA256` 來自 `CommonCrypto`，需要在檔案頂部加 `import CommonCrypto`（或用 `CryptoKit` 的 `SHA256`）。實作時用 `CryptoKit` 更現代：

```swift
import CryptoKit

// 替換 sha256Hex 實作：
private static func sha256Hex(of url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
```

**Step 2: 驗證編譯**

```bash
cd /Users/fredchu/dev/verbatim-flow/apps/mac-client && swift build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/PythonEnvironmentManager.swift
git commit -m "feat: add PythonEnvironmentManager for on-demand venv setup"
```

---

### Task 3: PythonScriptRunner — 加入 Application Support 候選路徑

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/PythonScriptRunner.swift:46-82`

**Step 1: 修改 resolvePythonExecutable**

在候選 3（exec-relative）之後、系統 python fallback 之前，加入 Application Support 路徑：

```swift
// 現有候選 1-3 之後加入：

// 4. Application Support venv (on-demand setup for distributed app)
let appSupportPython = PythonEnvironmentManager.appSupportPythonURL
candidates.append(appSupportPython)
```

移除系統 python fallback（最後幾行）：

```swift
// 刪除這段：
// let systemPython = URL(fileURLWithPath: "/usr/bin/python3")
// if fileManager.fileExists(atPath: systemPython.path) {
//     return systemPython
// }
```

**Step 2: 驗證編譯**

```bash
cd /Users/fredchu/dev/verbatim-flow/apps/mac-client && swift build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/PythonScriptRunner.swift
git commit -m "feat: add Application Support venv path, remove system python fallback"
```

---

### Task 4: MenuBarApp — 啟動時觸發 setup + 通知

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/MenuBarApp.swift:341-356`

**Step 1: 在 applicationDidFinishLaunching 加入 venv setup**

在 `controller.start()` 之前加入：

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    TerminologyDictionary.ensureDictionaryFileExists()
    OpenAISettings.ensureConfigFileExists()
    setupStatusItem()
    setupMenu()
    bindControllerCallbacks()

    // On-demand Python environment setup
    PythonEnvironmentManager.ensureReady { [weak self] status in
        DispatchQueue.main.async {
            self?.handlePythonEnvStatus(status)
        }
    }

    controller.setClarifyHotkey(initialClarifyHotkey)
    controller.start()
    refreshModeChecks()
    refreshEngineChecks()
    refreshHotkeyChecks()
    refreshLanguageChecks()
    refreshRecentTranscriptMenu()
    refreshPermissionStatus(controller.currentPermissionSnapshot())
}
```

**Step 2: 加入 handlePythonEnvStatus 方法**

在 MenuBarApp 內加入：

```swift
private func handlePythonEnvStatus(_ status: PythonEnvStatus) {
    switch status {
    case .ready:
        stateMenuItem.title = "State: Ready"
    case .setting(let message):
        stateMenuItem.title = "State: \(message)"
        sendNotification(title: "VerbatimFlow", body: message)
    case .failed(let message):
        stateMenuItem.title = "State: Python setup failed"
        showAlert(
            title: "Python Environment Setup Failed",
            message: "\(message)\n\nApple speech engine is still available. Python-based engines (MLX Whisper, Qwen, Whisper) require a working Python environment.",
            style: .warning
        )
    case .noPython:
        showAlert(
            title: "Python Not Found",
            message: "VerbatimFlow requires Python 3 for advanced speech engines.\n\nInstall via: xcode-select --install\n\nApple speech engine is still available without Python.",
            style: .warning
        )
    }
}

private func sendNotification(title: String, body: String) {
    let notification = NSUserNotification()
    notification.title = title
    notification.informativeText = body
    NSUserNotificationCenter.default.deliver(notification)
}

private func showAlert(title: String, message: String, style: NSAlert.Style) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = style
    alert.addButton(withTitle: "OK")
    alert.runModal()
}
```

注意：`NSUserNotification` 在 macOS 13+ 已棄用。如果目標是 macOS 13+，改用 `UNUserNotificationCenter`：

```swift
import UserNotifications

private func sendNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
}
```

實作時選擇 `UNUserNotificationCenter`（現代 API）。

**Step 3: 驗證編譯**

```bash
cd /Users/fredchu/dev/verbatim-flow/apps/mac-client && swift build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/MenuBarApp.swift
git commit -m "feat: trigger on-demand Python venv setup at app launch"
```

---

### Task 5: 清理 env var hack

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/PythonScriptRunner.swift`
- Delete: `~/Library/LaunchAgents/com.verbatimflow.python-env.plist`

**Step 1: 保留 env var 候選但調整註解**

env var override 保留（開發者有用），但把註解從 "highest priority" 改為 "developer override"。已在 Task 3 中處理。

**Step 2: 移除 LaunchAgent plist**

```bash
launchctl unload ~/Library/LaunchAgents/com.verbatimflow.python-env.plist
rm ~/Library/LaunchAgents/com.verbatimflow.python-env.plist
```

注意：不需要 commit，plist 不在 repo 內。

---

### Task 6: 整合測試

**Step 1: Build app**

```bash
cd /Users/fredchu/dev/verbatim-flow && bash scripts/build-native-app.sh
```

**Step 2: 驗證 bundle 內容**

```bash
ls -la apps/mac-client/dist/VerbatimFlow.app/Contents/Resources/python/requirements.txt
```

**Step 3: 模擬首次安裝（移除 Application Support venv）**

```bash
rm -rf ~/Library/Application\ Support/VerbatimFlow/.venv
rm -f ~/Library/Application\ Support/VerbatimFlow/.requirements_hash
```

**Step 4: 從 dist 啟動 app**

```bash
open apps/mac-client/dist/VerbatimFlow.app
```

Expected:
- 系統通知：「Installing Python packages...」
- menu bar stateMenuItem 顯示安裝進度
- 安裝完成後 venv 存在於 `~/Library/Application Support/VerbatimFlow/.venv/`
- `.requirements_hash` 檔案已寫入
- MLX Whisper 引擎可正常轉錄

**Step 5: 驗證 hash 比對（不重建）**

```bash
# 關閉 app 後重新開啟
open apps/mac-client/dist/VerbatimFlow.app
```

Expected: 不觸發重建，直接就緒。

**Step 6: 驗證 graceful degradation**

```bash
# 模擬 Python 不可用
mv /usr/bin/python3 /usr/bin/python3.bak  # 需要 sudo，或改用其他方式測試
```

替代測試：暫時把 requirements.txt 從 bundle 移除，重建 app 再啟動，確認 alert 出現且 Apple 引擎可用。
