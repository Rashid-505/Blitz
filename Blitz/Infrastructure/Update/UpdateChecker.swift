import Foundation
import AppKit

// MARK: - UpdateChecker

/// Checks GitHub Releases for a newer version of Blitz and, if found,
/// downloads the .dmg, mounts it, and installs it via a detached shell
/// script that runs after the app terminates.
///
/// Replace `repoOwner` / `repoName` with the actual GitHub repository.
@Observable
final class UpdateChecker {

    // MARK: - Configuration

    static let repoOwner = "rashidhuseynov"
    static let repoName  = "Blitz"

    // MARK: - State

    enum State {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(progress: Double)
        case error(String)

        var isIdle: Bool { if case .idle = self { return true }; return false }
        var isChecking: Bool { if case .checking = self { return true }; return false }

        /// Extracts the progress value (0–1) from the .downloading case.
        var downloadProgress: Double? {
            if case .downloading(let p) = self { return p }
            return nil
        }
    }

    struct Release: Sendable {
        let version: String
        let releaseURL: URL
        let dmgURL: URL
    }

    private(set) var state: State = .idle

    // MARK: - Public API

    func checkForUpdates() async {
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            state = release.version.isNewerThan(current) ? .available(release) : .upToDate
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Downloads the .dmg, mounts it, writes an installer script, then
    /// terminates the app so the script can replace the binary and relaunch.
    func downloadAndInstall(_ release: Release) async {
        state = .downloading(progress: 0)
        do {
            // URLSession suspends this task on background threads while
            // downloading — the main actor remains free during the wait.
            let (tempURL, response) = try await URLSession.shared.download(from: release.dmgURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError.downloadFailed
            }

            let dmgURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Blitz-Update-\(release.version).dmg")
            try? FileManager.default.removeItem(at: dmgURL)
            try FileManager.default.moveItem(at: tempURL, to: dmgURL)

            state = .downloading(progress: 1.0)

            // Mount the DMG and prepare the installer script on a background
            // thread — hdiutil attach can block for a few seconds.
            let installPath = Bundle.main.bundlePath
            let pid = ProcessInfo.processInfo.processIdentifier
            try await Task.detached(priority: .userInitiated) {
                try UpdateChecker.mountAndScheduleInstall(
                    dmgURL: dmgURL, installPath: installPath, parentPID: pid
                )
            }.value

            // The installer script is now running detached and waiting for
            // us to quit. Terminate so it can replace the app bundle.
            NSApp.terminate(nil)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func openReleasePage(_ release: Release) {
        NSWorkspace.shared.open(release.releaseURL)
    }

    func reset() {
        state = .idle
    }

    // MARK: - GitHub API

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest") else {
            throw UpdateError.apiError
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.apiError
        }

        let gh = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = gh.tag_name.trimmingCharacters(in: .init(charactersIn: "vV"))

        guard let releaseURL = URL(string: gh.html_url) else { throw UpdateError.apiError }
        guard let asset = gh.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let dmgURL = URL(string: asset.browser_download_url) else {
            throw UpdateError.noDMGAsset
        }

        return Release(version: version, releaseURL: releaseURL, dmgURL: dmgURL)
    }

    // MARK: - Mount + install

    /// Mounts the downloaded .dmg, finds the .app inside, then writes and
    /// launches a shell script that waits for the parent process to exit,
    /// copies the new bundle over the old one, and relaunches.
    ///
    /// `nonisolated` so it can be called from `Task.detached` without
    /// hopping back to the main actor.
    nonisolated static func mountAndScheduleInstall(
        dmgURL: URL,
        installPath: String,
        parentPID: Int32
    ) throws {
        // Mount the DMG; request plist output for reliable mount-point parsing.
        let mountTask = Process()
        mountTask.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mountTask.arguments     = ["attach", "-noautoopen", "-nobrowse", "-plist", dmgURL.path]
        let outPipe = Pipe()
        mountTask.standardOutput = outPipe
        mountTask.standardError  = Pipe()
        try mountTask.run()
        mountTask.waitUntilExit()
        guard mountTask.terminationStatus == 0 else { throw UpdateError.mountFailed }

        let plistData = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let plist     = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
            let entities  = plist["system-entities"] as? [[String: Any]],
            let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).last
        else { throw UpdateError.mountFailed }

        // Locate the .app bundle inside the mounted volume.
        let contents = try FileManager.default.contentsOfDirectory(atPath: mountPoint)
        guard let appDir = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError.appNotFound
        }
        let sourceApp = (mountPoint as NSString).appendingPathComponent(appDir)

        // Write the installer script.  It waits for the parent PID to
        // disappear (more reliable than grepping by name), copies the new
        // bundle into place, unmounts the DMG, then relaunches.
        let script = """
        #!/bin/bash
        while kill -0 \(parentPID) 2>/dev/null; do sleep 0.2; done
        rm -rf \(q(installPath))
        cp -Rp \(q(sourceApp)) \(q(installPath))
        hdiutil detach \(q(mountPoint)) -quiet 2>/dev/null || true
        sleep 0.3
        open \(q(installPath))
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitz_update_\(parentPID).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        // Launch detached — we do NOT wait for it to finish.
        let launcher = Process()
        launcher.executableURL  = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments      = [scriptURL.path]
        launcher.standardOutput = FileHandle.nullDevice
        launcher.standardError  = FileHandle.nullDevice
        try launcher.run()
    }

    nonisolated private static func q(_ s: String) -> String {
        "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case apiError, noDMGAsset, downloadFailed, mountFailed, appNotFound

    var errorDescription: String? {
        switch self {
        case .apiError:       return "Unable to reach GitHub. Check your internet connection."
        case .noDMGAsset:     return "No .dmg file found in the latest GitHub release."
        case .downloadFailed: return "The update download failed."
        case .mountFailed:    return "Could not mount the update disk image."
        case .appNotFound:    return "Blitz.app was not found in the disk image."
        }
    }
}

// MARK: - Version comparison

private extension String {
    /// Returns true when `self` represents a higher semver than `other`.
    func isNewerThan(_ other: String) -> Bool {
        let a = versionInts()
        let b = other.versionInts()
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func versionInts() -> [Int] {
        split(separator: ".").compactMap { Int($0) }
    }
}
