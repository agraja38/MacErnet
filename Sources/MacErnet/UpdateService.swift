import AppKit
import CryptoKit
import Darwin
import Foundation

struct UpdateManifest: Decodable {
    let version: String
    let build: Int
    let notes: String
    let arm64AssetURL: String
    let x86_64AssetURL: String
    let sha256: String?
}

enum UpdateInstallerScript {
    static let contents = """
    #!/bin/zsh
    set -euo pipefail
    SOURCE_APP="$1"
    TARGET_APP="$2"
    MOUNT_POINT="$3"
    DISK_IMAGE="$4"
    APP_PID="$5"
    BACKUP_APP="${TARGET_APP}.previous"

    /bin/sleep 0.5
    if /bin/kill -0 "$APP_PID" 2>/dev/null; then
      /bin/kill -TERM "$APP_PID" 2>/dev/null || true
    fi
    for attempt in {1..50}; do
      if ! /bin/kill -0 "$APP_PID" 2>/dev/null; then break; fi
      /bin/sleep 0.1
    done
    if /bin/kill -0 "$APP_PID" 2>/dev/null; then
      /bin/kill -KILL "$APP_PID" 2>/dev/null || true
    fi
    for attempt in {1..20}; do
      if ! /bin/kill -0 "$APP_PID" 2>/dev/null; then break; fi
      /bin/sleep 0.1
    done

    /bin/rm -rf "$BACKUP_APP"
    if [[ -e "$TARGET_APP" ]]; then /bin/mv "$TARGET_APP" "$BACKUP_APP"; fi
    if /usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"; then
      /usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null || true
      if [[ "${MACERNET_UPDATE_TESTING:-0}" != "1" ]]; then
        if ! /usr/bin/open "$TARGET_APP"; then
          /bin/rm -rf "$TARGET_APP"
          if [[ -e "$BACKUP_APP" ]]; then /bin/mv "$BACKUP_APP" "$TARGET_APP"; fi
          /usr/bin/open "$TARGET_APP" 2>/dev/null || true
          exit 1
        fi
      fi
      /bin/rm -rf "$BACKUP_APP"
    else
      /bin/rm -rf "$TARGET_APP"
      if [[ -e "$BACKUP_APP" ]]; then /bin/mv "$BACKUP_APP" "$TARGET_APP"; fi
      if [[ "${MACERNET_UPDATE_TESTING:-0}" != "1" ]]; then
        /usr/bin/open "$TARGET_APP" 2>/dev/null || true
      fi
      exit 1
    fi
    if [[ "${MACERNET_UPDATE_TESTING:-0}" != "1" ]]; then
      /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet || true
    fi
    /bin/rm -f "$DISK_IMAGE" "$0"
    """
}

@MainActor
final class UpdateService {
    private enum UpdateError: LocalizedError {
        case invalidResponse
        case invalidAssetURL
        case invalidDiskImage
        case appMissing
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "The update server returned an invalid response."
            case .invalidAssetURL: return "The update feed contains an invalid download URL."
            case .invalidDiskImage: return "macOS could not mount the downloaded update."
            case .appMissing: return "The update does not contain MacErnet.app."
            case .checksumMismatch: return "The downloaded update failed its integrity check."
            }
        }
    }

    private let session: URLSession
    private let manifestURL: URL
    private var isChecking = false
    private var progressAlert: NSAlert?
    private var progressHostWindow: NSWindow?

    init(session: URLSession = .shared) {
        self.session = session
        let configuredURL = Bundle.main.object(forInfoDictionaryKey: "MacErnetUpdateManifestURL") as? String
        let fallback = "https://raw.githubusercontent.com/agraja38/app-update-feeds/main/macernet/update.json"
        self.manifestURL = URL(string: configuredURL ?? fallback)!
    }

    func checkForUpdates(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true

        Task {
            defer { isChecking = false }
            do {
                let manifest = try await fetchManifest()
                let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
                guard VersionComparator.isNewer(manifest.version, than: currentVersion) else {
                    if userInitiated {
                        showInformation(title: "MacErnet is up to date", message: "You are running version \(currentVersion).")
                    }
                    return
                }
                promptToInstall(manifest)
            } catch {
                if userInitiated {
                    showError(title: "Couldn’t Check for Updates", error: error)
                }
            }
        }
    }

    private func fetchManifest() async throws -> UpdateManifest {
        var request = URLRequest(url: manifestURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.invalidResponse
        }
        return try JSONDecoder().decode(UpdateManifest.self, from: data)
    }

    private func promptToInstall(_ manifest: UpdateManifest) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "MacErnet \(manifest.version) is available"
        alert.informativeText = manifest.notes
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Later")
        NSApplication.shared.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            downloadAndInstall(manifest)
        }
    }

    private func downloadAndInstall(_ manifest: UpdateManifest) {
        showProgress(for: manifest.version)

        Task {
            do {
                let sourceURL = try assetURL(for: manifest)
                let (temporaryURL, response) = try await session.download(from: sourceURL)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw UpdateError.invalidResponse
                }

                let diskImageURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MacErnet-\(manifest.version)-\(UUID().uuidString).dmg")
                try FileManager.default.moveItem(at: temporaryURL, to: diskImageURL)
                try verifyChecksum(of: diskImageURL, expected: manifest.sha256)
                let mountPoint = try mountDiskImage(at: diskImageURL)
                try launchInstaller(mountPoint: mountPoint, diskImageURL: diskImageURL)
                quitForUpdate()
            } catch {
                dismissProgress()
                showError(title: "Couldn’t Install Update", error: error)
            }
        }
    }

    private func assetURL(for manifest: UpdateManifest) throws -> URL {
        #if arch(arm64)
        let value = manifest.arm64AssetURL
        #else
        let value = manifest.x86_64AssetURL
        #endif
        guard let url = URL(string: value) else { throw UpdateError.invalidAssetURL }
        return url
    }

    private func verifyChecksum(of fileURL: URL, expected: String?) throws {
        guard let expected, !expected.isEmpty else { return }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(expected) == .orderedSame else {
            throw UpdateError.checksumMismatch
        }
    }

    private func mountDiskImage(at diskImageURL: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-nobrowse", "-plist", diskImageURL.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.invalidDiskImage }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard
            let root = plist as? [String: Any],
            let entities = root["system-entities"] as? [[String: Any]],
            let path = entities.compactMap({ $0["mount-point"] as? String }).first
        else { throw UpdateError.invalidDiskImage }
        return URL(fileURLWithPath: path)
    }

    private func launchInstaller(mountPoint: URL, diskImageURL: URL) throws {
        let sourceApp = mountPoint.appendingPathComponent("MacErnet.app")
        guard FileManager.default.fileExists(atPath: sourceApp.path) else { throw UpdateError.appMissing }

        let currentApp = Bundle.main.bundleURL
        let targetApp = currentApp.pathExtension == "app"
            ? currentApp
            : URL(fileURLWithPath: "/Applications/MacErnet.app")
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macernet-update-\(UUID().uuidString).sh")
        try UpdateInstallerScript.contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        installer.arguments = [
            "/bin/zsh",
            scriptURL.path,
            sourceApp.path,
            targetApp.path,
            mountPoint.path,
            diskImageURL.path,
            String(ProcessInfo.processInfo.processIdentifier)
        ]
        installer.standardInput = FileHandle.nullDevice
        installer.standardOutput = FileHandle.nullDevice
        installer.standardError = FileHandle.nullDevice
        try installer.run()
    }

    private func showProgress(for version: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Downloading MacErnet \(version)…"
        alert.informativeText = "The app will reopen when installation is complete."
        alert.addButton(withTitle: "Please Wait")
        alert.buttons.first?.isEnabled = false

        let hostWindow: NSWindow
        if let keyWindow = NSApp.keyWindow {
            hostWindow = keyWindow
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.alphaValue = 0
            window.orderFront(nil)
            progressHostWindow = window
            hostWindow = window
        }

        progressAlert = alert
        alert.beginSheetModal(for: hostWindow)
    }

    private func dismissProgress() {
        if let window = progressAlert?.window, let parent = window.sheetParent {
            parent.endSheet(window)
        }
        progressAlert = nil
        progressHostWindow?.orderOut(nil)
        progressHostWindow = nil
    }

    private func quitForUpdate() {
        dismissProgress()

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
            _exit(EXIT_SUCCESS)
        }
        NSApplication.shared.terminate(nil)
    }

    private func showInformation(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func showError(title: String, error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.runModal()
    }
}
