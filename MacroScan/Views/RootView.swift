import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "chart.bar.fill")
                }

            DiningView()
                .tabItem {
                    Label("Dining", systemImage: "building.2")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onAppear {
            ensureUserProfile()
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
        .modelContainer(for: [Food.self, LogEntry.self, UserProfile.self, DiningMenu.self], inMemory: true)
}
