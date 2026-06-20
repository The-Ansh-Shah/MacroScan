import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

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
        .tint(Color.mAccent)
        .onAppear {
            configureTabBarAppearance()
            ensureUserProfile()
            SeedLibrary.seedIfNeeded(into: modelContext)
            SeedLibrary.removeLegacySeededRecipesIfNeeded(into: modelContext)
            if let profile = profiles.first, profile.heightIn == nil && profile.ageYears == nil {
                showingOnboarding = true
            }
            // Refresh local notification content from today's data on each launch.
            if let profile = profiles.first, profile.notificationsEnabled {
                let repo = FoodRepository(modelContext: modelContext)
                Task { @MainActor in
                    await NotificationService.reschedule(profile: profile, repo: repo)
                }
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

    /// Apply a clean, translucent tab bar that keeps the system blur.
    private func configureTabBarAppearance() {
        #if canImport(UIKit)
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        #endif
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Food.self, LogEntry.self, UserProfile.self, BodyMeasurement.self, WeightGoal.self], inMemory: true)
}
