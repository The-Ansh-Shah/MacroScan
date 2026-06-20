import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var showingOnboarding = false

    var body: some View {
        TabView {
            TodayTabView()
                .tabItem {
                    Label("Today", systemImage: "chart.bar.fill")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }

            MeView()
                .tabItem {
                    Label("Me", systemImage: "person.crop.circle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onAppear {
            ensureUserProfile()
            SeedLibrary.seedIfNeeded(into: modelContext)
            if let profile = profiles.first, profile.heightIn == nil && profile.ageYears == nil {
                showingOnboarding = true
            }
        }
        .sheet(isPresented: $showingOnboarding) {
            if let profile = profiles.first {
                ProfileSetupView(profile: profile)
            }
        }
    }

    /// Create a default UserProfile if none exists (singleton pattern)
    private func ensureUserProfile() {
        if profiles.isEmpty {
            let profile = UserProfile()
            modelContext.insert(profile)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Food.self, LogEntry.self, UserProfile.self, BodyMeasurement.self, WeightGoal.self], inMemory: true)
}
