import SwiftUI

struct ContentView: View {
    @ObservedObject private var syncViewModel = SyncViewModel.shared
    @EnvironmentObject var importState: ImportState
    @ObservedObject private var profileStore = ProfileStore.shared

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "heart.text.square")
                }

            SyncDashboardView(vm: syncViewModel)
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }

            SettingsView(syncViewModel: syncViewModel)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(Color("Brand"))
        .environmentObject(syncViewModel)
        // The questionnaire comes first: nothing on Today works without a profile.
        .fullScreenCover(isPresented: Binding(
            get: { profileStore.profile == nil },
            set: { _ in })) {
            OnboardingView(isEditing: false)
        }
    }
}
