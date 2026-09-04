import FoundationModels

enum AppleIntelligenceCapability {

    enum Status: Equatable {
        case available
        case notEnabled
        case notEligible
        case modelNotReady

        var isAvailable: Bool { self == .available }

        var description: String {
            switch self {
            case .available:
                return "Available and ready"
            case .notEnabled:
                return "Apple Intelligence is not enabled. Turn it on in System Settings → Apple Intelligence & Siri."
            case .notEligible:
                return "This device does not support Apple Intelligence."
            case .modelNotReady:
                return "Apple Intelligence model is still downloading."
            }
        }
    }

    static var status: Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.deviceNotEligible):
            return .notEligible
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .notEligible
        }
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }
}
