import Foundation
import SwiftData

/// A single point-in-time body composition snapshot.
/// Users log these periodically; `BodyCompositionView` charts the history.
@Model
final class BodyMeasurement {
    var recordedAt: Date
    var weightLb: Double
    var bodyFatPct: Double?
    var waistIn: Double?
    var neckIn: Double?
    var hipIn: Double?
    var bodyFatSourceRaw: String?
    var notes: String?
    var source: String = "manual"
    var exportID: UUID = UUID()

    var bodyFatSource: BodyFatSource? {
        get {
            guard let raw = bodyFatSourceRaw else { return nil }
            return BodyFatSource(rawValue: raw)
        }
        set { bodyFatSourceRaw = newValue?.rawValue }
    }

    init(
        recordedAt: Date = Date(),
        weightLb: Double,
        bodyFatPct: Double? = nil,
        waistIn: Double? = nil,
        neckIn: Double? = nil,
        hipIn: Double? = nil,
        bodyFatSource: BodyFatSource? = nil,
        notes: String? = nil,
        source: String = "manual"
    ) {
        self.recordedAt = recordedAt
        self.weightLb = weightLb
        self.bodyFatPct = bodyFatPct
        self.waistIn = waistIn
        self.neckIn = neckIn
        self.hipIn = hipIn
        self.bodyFatSourceRaw = bodyFatSource?.rawValue
        self.notes = notes
        self.source = source
    }
}

enum BodyFatSource: String, Codable {
    case navy
    case manual
    case healthkit
}
