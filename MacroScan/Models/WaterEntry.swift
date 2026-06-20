import Foundation
import SwiftData

@Model
final class WaterEntry {
    var recordedAt: Date
    var amountMl: Double
    var source: String
    var exportID: UUID = UUID()

    init(amountMl: Double, recordedAt: Date = Date(), source: String = "manual") {
        self.amountMl = amountMl
        self.recordedAt = recordedAt
        self.source = source
    }
}
