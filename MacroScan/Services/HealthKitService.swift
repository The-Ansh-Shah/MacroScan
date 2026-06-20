import Foundation
#if canImport(HealthKit)
import HealthKit

actor HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard isAvailable else { return }

        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.stepCount),
        ]

        let writeTypes: Set<HKSampleType> = [
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietaryFiber),
            HKQuantityType(.dietaryWater),
        ]

        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        store.authorizationStatus(for: type)
    }

    // MARK: - Read: Weight

    func latestWeightLb() async throws -> (lb: Double, recordedAt: Date)? {
        guard isAvailable else { return nil }
        let type = HKQuantityType(.bodyMass)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let healthStore = store
        let sample = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKQuantitySample?, Error>) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDesc]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            healthStore.execute(query)
        }
        guard let sample else { return nil }
        let lb = sample.quantity.doubleValue(for: .pound())
        return (lb: lb, recordedAt: sample.startDate)
    }

    func latestBodyFatPct() async throws -> (pct: Double, recordedAt: Date)? {
        guard isAvailable else { return nil }
        let type = HKQuantityType(.bodyFatPercentage)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let healthStore = store
        let sample = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKQuantitySample?, Error>) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDesc]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            healthStore.execute(query)
        }
        guard let sample else { return nil }
        let pct = sample.quantity.doubleValue(for: .percent()) * 100
        return (pct: pct, recordedAt: sample.startDate)
    }

    // MARK: - Read: Energy & Steps

    func activeEnergyBurned(forDate date: Date) async throws -> Double {
        try await sumForDay(type: HKQuantityType(.activeEnergyBurned), date: date, unit: .kilocalorie())
    }

    func basalEnergyBurned(forDate date: Date) async throws -> Double {
        try await sumForDay(type: HKQuantityType(.basalEnergyBurned), date: date, unit: .kilocalorie())
    }

    func stepCount(forDate date: Date) async throws -> Int {
        let sum = try await sumForDay(type: HKQuantityType(.stepCount), date: date, unit: .count())
        return Int(sum)
    }

    // MARK: - Write: Water

    func writeWater(ml: Double, recordedAt: Date) async throws {
        guard isAvailable else { return }
        let type = HKQuantityType(.dietaryWater)
        let qty = HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml)
        let sample = HKQuantitySample(type: type, quantity: qty, start: recordedAt, end: recordedAt)
        try await store.save(sample)
    }

    // MARK: - Write: Nutrition

    func writeNutrition(_ entry: LogEntry) async throws {
        guard isAvailable else { return }
        let macros = await MainActor.run { entry.scaledMacros }
        let loggedAt = await MainActor.run { entry.loggedAt }

        let pairs: [(HKQuantityTypeIdentifier, Double, HKUnit)] = [
            (.dietaryEnergyConsumed, macros.calories, .kilocalorie()),
            (.dietaryProtein, macros.proteinG, .gram()),
            (.dietaryCarbohydrates, macros.carbsG, .gram()),
            (.dietaryFatTotal, macros.fatG, .gram()),
            (.dietaryFiber, macros.fiberG, .gram()),
        ]

        for (id, value, unit) in pairs where value > 0 {
            let type = HKQuantityType(id)
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            let sample = HKQuantitySample(type: type, quantity: quantity, start: loggedAt, end: loggedAt)
            try await store.save(sample)
        }
    }

    // MARK: - Write: Body Measurement

    func writeBodyMeasurement(_ measurement: BodyMeasurement) async throws {
        guard isAvailable else { return }
        let weightLb = await MainActor.run { measurement.weightLb }
        let bodyFatPct = await MainActor.run { measurement.bodyFatPct }
        let recordedAt = await MainActor.run { measurement.recordedAt }

        let massType = HKQuantityType(.bodyMass)
        let massQuantity = HKQuantity(unit: .pound(), doubleValue: weightLb)
        let massSample = HKQuantitySample(type: massType, quantity: massQuantity, start: recordedAt, end: recordedAt)
        try await store.save(massSample)

        if let bf = bodyFatPct {
            let bfType = HKQuantityType(.bodyFatPercentage)
            let bfQuantity = HKQuantity(unit: .percent(), doubleValue: bf / 100.0)
            let bfSample = HKQuantitySample(type: bfType, quantity: bfQuantity, start: recordedAt, end: recordedAt)
            try await store.save(bfSample)
        }
    }

    // MARK: - Helpers

    private func sumForDay(type: HKQuantityType, date: Date, unit: HKUnit) async throws -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let healthStore = store

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error { continuation.resume(throwing: error); return }
                let sum = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: sum)
            }
            healthStore.execute(query)
        }
    }
}

#else
// Stub for platforms without HealthKit (macOS, simulator edge cases)
actor HealthKitService {
    static let shared = HealthKitService()
    var isAvailable: Bool { false }
    func requestAuthorization() async throws {}
    func latestWeightLb() async throws -> (lb: Double, recordedAt: Date)? { nil }
    func latestBodyFatPct() async throws -> (pct: Double, recordedAt: Date)? { nil }
    func activeEnergyBurned(forDate: Date) async throws -> Double { 0 }
    func basalEnergyBurned(forDate: Date) async throws -> Double { 0 }
    func stepCount(forDate: Date) async throws -> Int { 0 }
    func writeWater(ml: Double, recordedAt: Date) async throws {}
    func writeNutrition(_ entry: LogEntry) async throws {}
    func writeBodyMeasurement(_ measurement: BodyMeasurement) async throws {}
}
#endif
