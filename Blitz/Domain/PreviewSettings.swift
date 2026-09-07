import Foundation

/// Stores the user's preference for whether transformed text should be previewed
/// before being written back to the source application.
///
/// Isolated from UserDefaults via a dedicated type so that
/// `TransformationOrchestrator` never reads UserDefaults directly,
/// keeping it testable with a simple initializer override.
@Observable
final class PreviewSettings {
    var isPreviewEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPreviewEnabled, forKey: Keys.previewEnabled)
        }
    }

    /// Reads the stored preference; defaults to `true` (preview on) on first launch.
    init() {
        if let stored = UserDefaults.standard.object(forKey: Keys.previewEnabled) as? Bool {
            isPreviewEnabled = stored
        } else {
            isPreviewEnabled = true
        }
    }

    /// Designated initializer for tests — bypasses UserDefaults entirely.
    init(isPreviewEnabled: Bool) {
        self.isPreviewEnabled = isPreviewEnabled
    }

    private enum Keys {
        static let previewEnabled = "blitz.preview.enabled"
    }
}
