import SwiftUI

@main
struct TalariaTrackerApp: App {
    @StateObject private var tracker = RideTracker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            RideView()
                .tabItem { Label("Ride", systemImage: "bicycle") }
            RoutesView()
                .tabItem { Label("Routes", systemImage: "map") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
        }
    }
}
