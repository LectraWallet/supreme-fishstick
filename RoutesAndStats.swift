import SwiftUI

struct RoutesView: View {
    @EnvironmentObject var tracker: RideTracker

    var body: some View {
        NavigationStack {
            List(HiddenRoute.all) { route in
                let unlocked = tracker.unlockedRoutes.contains(route.id)
                HStack(spacing: 14) {
                    Image(systemName: unlocked ? route.icon : "lock.fill")
                        .font(.largeTitle)
                        .foregroundStyle(unlocked ? .purple : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(unlocked ? route.name : "???")
                            .font(.headline)
                        Text(unlocked ? route.tagline : route.requirement.hint)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !unlocked {
                            ProgressView(value: route.requirement.progress(
                                totalDistance: tracker.totalDistance,
                                totalRides: tracker.totalRides,
                                topSpeed: tracker.topSpeed))
                                .tint(.purple)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Hidden Routes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(tracker.unlockedRoutes.count)/\(HiddenRoute.all.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct StatsView: View {
    @EnvironmentObject var tracker: RideTracker
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        bigStat("Total distance", Format.distance(tracker.totalDistance, mph: tracker.useMph), "map")
                        bigStat("Rides", "\(tracker.totalRides)", "bicycle")
                        bigStat("Ride time", Format.time(tracker.totalTime), "clock")
                        bigStat("Top speed", Format.speed(tracker.topSpeed, mph: tracker.useMph), "gauge")
                    }
                    Toggle("Use mph / miles", isOn: Binding(
                        get: { tracker.useMph },
                        set: { _ in tracker.toggleUnits() }
                    ))
                    .padding()
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(12)

                    Button("Reset all data", role: .destructive) {
                        confirmReset = true
                    }
                    .confirmationDialog("Delete everything?", isPresented: $confirmReset) {
                        Button("Delete all rides & stats", role: .destructive) {
                            tracker.resetAll()
                        }
                    } message: {
                        Text("This erases every ride, stat, and unlocked route.")
                    }
                }
                .padding()
            }
            .navigationTitle("Stats")
        }
    }

    private func bigStat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.purple)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(16)
    }
}
