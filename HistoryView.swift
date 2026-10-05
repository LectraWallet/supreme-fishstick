import SwiftUI
import MapKit

struct HistoryView: View {
    @EnvironmentObject var tracker: RideTracker

    var body: some View {
        NavigationStack {
            Group {
                if tracker.rides.isEmpty {
                    ContentUnavailableView(
                        "No rides yet",
                        systemImage: "bicycle",
                        description: Text("Finish a ride and it will show up here.")
                    )
                } else {
                    List {
                        ForEach(tracker.rides) { ride in
                            NavigationLink {
                                RideDetailView(ride: ride)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ride.startDate, style: .date)
                                            .font(.headline)
                                        Text("\(Format.distance(ride.distance, mph: tracker.useMph)) • \(Format.time(ride.duration)) • \(Format.speed(ride.maxSpeed, mph: tracker.useMph)) top")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        if let tag = ride.routeTag {
                                            Text(tag).font(.caption).foregroundStyle(.purple)
                                        }
                                    }
                                    Spacer()
                                    if let c = ride.chase {
                                        Image(systemName: c == .escaped ? "trophy.fill" : "exclamationmark.triangle.fill")
                                            .foregroundStyle(c == .escaped ? .green : .red)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            for i in idx { tracker.deleteRide(tracker.rides[i]) }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

struct RideDetailView: View {
    @EnvironmentObject var tracker: RideTracker
    let ride: Ride

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapCard
                statsGrid
                if !ride.note.isEmpty {
                    Text("“\(ride.note)”")
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let tag = ride.routeTag {
                    Label("Tagged: \(tag)", systemImage: "tag")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.purple)
                }
                if let cn = ride.chaserName, let c = ride.chase {
                    Label(c == .escaped ? "Escaped \(cn)" : "Caught by \(cn)",
                          systemImage: c == .escaped ? "trophy" : "exclamationmark.triangle")
                        .foregroundStyle(c == .escaped ? .green : .red)
                }
                ShareLink("Export GPX", item: gpxFileURL())
                    .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(ride.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var mapCard: some View {
        let coords = ride.points.map(\.coordinate)
        return Map(initialPosition: region(for: coords)) {
            if coords.count > 1 {
                MapPolyline(coordinates: coords)
                    .stroke(.purple, lineWidth: 4)
            }
            if let first = coords.first {
                Annotation("Start", coordinate: first) {
                    Image(systemName: "circle.fill").foregroundStyle(.green)
                }
            }
            if let last = coords.last, coords.count > 1 {
                Annotation("End", coordinate: last) {
                    Image(systemName: "flag.fill").foregroundStyle(.red)
                }
            }
        }
        .frame(height: 260)
        .cornerRadius(16)
    }

    private func region(for coords: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard !coords.isEmpty else { return .automatic }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (lats.max()! - lats.min()!) * 1.4),
            longitudeDelta: max(0.01, (lons.max()! - lons.min()!) * 1.4))
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard("Distance", Format.distance(ride.distance, mph: tracker.useMph))
            statCard("Duration", Format.time(ride.duration))
            statCard("Top speed", Format.speed(ride.maxSpeed, mph: tracker.useMph))
            statCard("Avg speed", Format.speed(ride.avgSpeed, mph: tracker.useMph))
            statCard("Climbing", "\(Int(ride.elevationGain)) m")
            statCard("GPS points", "\(ride.points.count)")
        }
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(12)
    }

    private func gpxFileURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ride-\(ride.id.uuidString).gpx")
        try? GPXExporter.gpx(for: ride).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
