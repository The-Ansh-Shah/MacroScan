import SwiftUI
import SwiftData

/// Water intake card shown on Today's DayView.
/// Shows oz consumed vs target, +8oz / +16oz / +custom quick-add buttons.
/// Tap the bar to open WaterDetailSheet.
struct WaterCard: View {
    let date: Date
    let profile: UserProfile
    @Environment(\.modelContext) private var modelContext

    @State private var totalMl: Double = 0
    @State private var showingDetail = false
    @State private var showingCustom = false
    @State private var customOzText = ""

    private var totalOz: Double { totalMl / 29.5735 }
    private var targetOz: Double { profile.dailyWaterTargetMl / 29.5735 }
    private var fraction: Double { targetOz > 0 ? min(totalOz / targetOz, 1.0) : 0 }

    private var barColor: Color {
        if fraction >= 1.0 { return Color.mOnTarget }
        if fraction >= 0.7 { return Color.mApproaching }
        return Color.mTextTertiary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label("Water", systemImage: "drop.fill")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mAccent)
                Spacer()
                Button {
                    showingDetail = true
                } label: {
                    Text("\(String(format: "%.0f", totalOz)) / \(String(format: "%.0f", targetOz)) oz")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                        .monospacedDigit()
                }
                .buttonStyle(.plain)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(barColor.opacity(0.15))
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * fraction)
                        .animation(.easeOut(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 8)
            .onTapGesture { showingDetail = true }

            HStack(spacing: Spacing.sm) {
                waterButton("+8 oz") { add(oz: 8) }
                waterButton("+16 oz") { add(oz: 16) }
                waterButton("+Custom") { showingCustom = true }
            }
        }
        .padding(Spacing.md)
        .mCard()
        .task(id: date) { await refresh() }
        .sheet(isPresented: $showingDetail, onDismiss: {
            Task { await refresh() }
        }) {
            WaterDetailSheet(date: date, profile: profile)
        }
        .alert("Add water", isPresented: $showingCustom) {
            TextField("oz", text: $customOzText)
                #if canImport(UIKit)
                .keyboardType(.decimalPad)
                #endif
            Button("Add") {
                if let oz = Double(customOzText), oz > 0 {
                    add(oz: oz)
                }
                customOzText = ""
            }
            Button("Cancel", role: .cancel) { customOzText = "" }
        }
    }

    @ViewBuilder
    private func waterButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.mCaption)
                .foregroundStyle(Color.mAccent)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule().fill(Color.mAccent.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private func add(oz: Double) {
        let ml = oz * 29.5735
        let repo = FoodRepository(modelContext: modelContext)
        repo.logWater(ml: ml, at: date)
        totalMl += ml
        Haptics.logFood()
    }

    @MainActor
    private func refresh() async {
        let repo = FoodRepository(modelContext: modelContext)
        totalMl = repo.totalWater(forDate: date)
    }
}

// MARK: - Detail Sheet

struct WaterDetailSheet: View {
    let date: Date
    let profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [WaterEntry] = []

    private var totalOz: Double { entries.reduce(0) { $0 + $1.amountMl } / 29.5735 }
    private var targetOz: Double { profile.dailyWaterTargetMl / 29.5735 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Total today")
                            .font(.mBody)
                        Spacer()
                        Text("\(String(format: "%.0f", totalOz)) / \(String(format: "%.0f", targetOz)) oz")
                            .font(.mBody)
                            .foregroundStyle(Color.mTextSecondary)
                            .monospacedDigit()
                    }
                }

                Section("Entries") {
                    if entries.isEmpty {
                        Text("No water logged yet")
                            .font(.mBody)
                            .foregroundStyle(Color.mTextTertiary)
                    } else {
                        ForEach(entries) { entry in
                            HStack {
                                Text(entry.recordedAt, format: .dateTime.hour().minute())
                                    .font(.mBody)
                                    .foregroundStyle(Color.mTextPrimary)
                                Spacer()
                                Text("\(String(format: "%.0f", entry.amountMl / 29.5735)) oz")
                                    .font(.mBody)
                                    .foregroundStyle(Color.mTextSecondary)
                                    .monospacedDigit()
                            }
                        }
                        .onDelete { indexSet in
                            let repo = FoodRepository(modelContext: modelContext)
                            for idx in indexSet {
                                repo.deleteWater(entries[idx])
                            }
                            entries.remove(atOffsets: indexSet)
                            Haptics.deleted()
                        }
                    }
                }
            }
            .navigationTitle("Water")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                let repo = FoodRepository(modelContext: modelContext)
                entries = repo.waterEntries(forDate: date)
            }
        }
    }
}
