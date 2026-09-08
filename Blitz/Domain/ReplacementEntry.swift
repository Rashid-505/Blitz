import SwiftData
import Foundation

@Model
final class ReplacementEntry {
    var scenarioName: String
    var originalText: String
    var resultText: String
    var date: Date

    init(scenarioName: String, originalText: String, resultText: String, date: Date = .now) {
        self.scenarioName = scenarioName
        self.originalText = originalText
        self.resultText = resultText
        self.date = date
    }
}
