import SwiftData
import Foundation

@Model
final class Scenario {
    var name: String
    var instruction: String
    var isEnabled: Bool
    var order: Int
    var isBuiltIn: Bool

    init(
        name: String,
        instruction: String,
        isEnabled: Bool = true,
        order: Int,
        isBuiltIn: Bool = false
    ) {
        self.name = name
        self.instruction = instruction
        self.isEnabled = isEnabled
        self.order = order
        self.isBuiltIn = isBuiltIn
    }
}
