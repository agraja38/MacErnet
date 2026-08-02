import AppKit
import CryptoKit
import Foundation

struct UpdateManifest: Decodable {
    let version: String
    let build: Int
    let notes: String
    let arm64AssetURL: String
    let x86_64AssetURL: String
    let sha256: String?
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
        let progress = NSAlert()
        progress.alertStyle = .informational
        progress.messageText = "Downloading MacErnet \(manifest.version)…"
        progress.informativeText = "The app will reopen when installation is complete."
        progress.addButton(withTitle: "Cancel")
        progress.buttons.first?.isEnabled = false
        progress.beginSheetModal(for: NSApp.keyWindow ?? makeProgressWindow())

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
                NSApplication.shared.terminate(nil)
            } catch {
                progress.window.sheetParent?.endSheet(progress.window)
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
        let script = """
        #!/bin/zsh
        set -euo pipefail
        SOURCE_APP="$1"
        TARGET_APP="$2"
        MOUNT_POINT="$3"
        DISK_IMAGE="$4"
        APP_PID="$5"
        BACKUP_APP="${TARGET_APP}.previous"

        while /bin/kill -0 "$APP_PID" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$BACKUP_APP"
        if [[ -e "$TARGET_APP" ]]; then /bin/mv "$TARGET_APP" "$BACKUP_APP"; fi
        if /usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"; then
          /usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null || true
          /usr/bin/open "$TARGET_APP"
          /bin/rm -rf "$BACKUP_APP"
        else
          /bin/rm -rf "$TARGET_APP"
          if [[ -e "$BACKUP_APP" ]]; then /bin/mv "$BACKUP_APP" "$TARGET_APP"; fi
          /usr/bin/open "$TARGET_APP" 2>/dev/null || true
        fi
        /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet || true
        /bin/rm -f "$DISK_IMAGE" "$0"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/bin/zsh")
        installer.arguments = [
            scriptURL.path,
            sourceApp.path,
            targetApp.path,
            mountPoint.path,
            diskImageURL.path,
            String(ProcessInfo.processInfo.processIdentifier)
        ]
        installer.standardOutput = FileHandle.nullDevice
        installer.standardError = FileHandle.nullDevice
        try installer.run()
    }

    private func makeProgressWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        window.orderFront(nil)
        return window
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
