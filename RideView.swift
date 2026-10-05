import SwiftUI
import MapKit

struct RideView: View {
    @EnvironmentObject var tracker: RideTracker
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var satellite = false
    @State private var selectedRouteTag: String? = nil
    @State private var showSummary = false
    @State private var finishedRide: Ride? = nil
    @State private var showCaught = false
    @State private var showChaseSetup = false
    @State private var noteText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                mapView
                VStack {
                    chaseBanner
                    Spacer()
                    bottomPanel
                }
            }
            .navigationTitle("Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(satellite ? "Satellite" : "Map") { satellite.toggle() }
                        .font(.caption)
                }
            }
            .onChange(of: tracker.caught) { _, isCaught in
                if isCaught { showCaught = true }
            }
            .onChange(of: tracker.completedRide) { _, ride in
                if let ride {
                    finishedRide = ride
                    noteText = ""
                    showSummary = true
                }
            }
            .sheet(isPresented: $showCaught) { caughtSheet }
            .sheet(isPresented: $showSummary) { summarySheet }
            .sheet(isPresented: $showChaseSetup) { ChaseSetupView() }
        }
    }

    // MARK: - Map

    private var mapView: some View {
        Map(position: $position) {
            UserAnnotation()
            if tracker.points.count > 1 {
                MapPolyline(coordinates: tracker.points.map(\.coordinate))
                    .stroke(.purple, lineWidth: 5)
            }
            if tracker.escapeRouteCoords.count > 1 {
                MapPolyline(coordinates: tracker.escapeRouteCoords)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 4, dash: [10, 6]))
            }
            if let dest = tracker.destination {
                Annotation("Escape", coordinate: dest) {
                    Image(systemName: "flag.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                }
            }
            if let cc = tracker.chaserCoord, let kind = tracker.chaser, tracker.state != .idle {
                Annotation(kind.name, coordinate: cc) {
                    Image(systemName: kind.icon)
                        .font(.system(size: 34))
                        .foregroundStyle(.red)
                }
            }
        }
        .mapStyle(satellite ? .imagery : .standard)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    // MARK: - Chase banner

    @ViewBuilder
    private var chaseBanner: some View {
        if let kind = tracker.chaser, let d = tracker.chaserDistance, tracker.state == .riding {
            HStack {
                Image(systemName: kind.icon)
                Text(kind.name.uppercased())
                    .font(.headline)
                Spacer()
                Text("\(Int(d)) m")
                    .font(.headline.monospacedDigit())
            }
            .padding()
            .background(chaseColor(d).opacity(0.85))
            .foregroundStyle(.white)
            .cornerRadius(14)
            .padding(.horizontal)
        }
    }

    private func chaseColor(_ d: Double) -> Color {
        if d > 150 { return .green }
        if d > 60 { return .orange }
        return .red
    }

    // MARK: - Bottom panels

    @ViewBuilder
    private var bottomPanel: some View {
        switch tracker.state {
        case .idle: startPanel
        case .riding: hudPanel
        case .paused: pausedPanel
        }
    }

    private var startPanel: some View {
        VStack(spacing: 12) {
            if tracker.authorization == .notDetermined {
                Button("Enable Location") { tracker.requestPermission() }
                    .buttonStyle(.borderedProminent)
            }
            if !tracker.unlockedRoutes.isEmpty {
                Menu {
                    Button("No tag") { selectedRouteTag = nil }
                    ForEach(tracker.unlockedRoutes.sorted(), id: \.self) { id in
                        if let r = HiddenRoute.all.first(where: { $0.id == id }) {
                            Button("\(r.name)") { selectedRouteTag = r.name }
                        }
                    }
                } label: {
                    Label(selectedRouteTag ?? "Tag a hidden route", systemImage: "tag")
                        .font(.subheadline)
                }
            }
            Button {
                tracker.startRide(chaser: nil, routeTag: selectedRouteTag)
            } label: {
                Text("START RIDE").font(.title2.bold()).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(tracker.authorization == .denied || tracker.authorization == .restricted)
            Button { showChaseSetup = true } label: {
                Label("CHASE MODE", systemImage: "figure.run")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(tracker.authorization == .denied || tracker.authorization == .restricted)
            Text("Chase mode routes you to an address through paths cars can't follow.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding()
    }

    private var hudPanel: some View {
        VStack(spacing: 10) {
            Text(Format.speed(tracker.currentSpeed, mph: tracker.useMph))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 24) {
                hudStat("Distance", Format.distance(tracker.currentDistance, mph: tracker.useMph))
                hudStat("Time", Format.time(tracker.elapsed))
                hudStat("Avg", Format.speed(tracker.currentAvgSpeed, mph: tracker.useMph))
                if tracker.destination != nil, let dd = tracker.distanceToDestination {
                    hudStat("Escape", Format.distance(dd, mph: tracker.useMph))
                }
            }
            HStack(spacing: 16) {
                Button { tracker.pauseRide() } label: {
                    Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { tracker.endRide() } label: {
                    Label("Finish", systemImage: "flag.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding()
    }

    private func hudStat(_ title: String, _ value: String) -> some View {
        VStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private var pausedPanel: some View {
        VStack(spacing: 12) {
            Text("Paused").font(.title2.bold())
            Text("\(Format.distance(tracker.currentDistance, mph: tracker.useMph)) • \(Format.time(tracker.elapsed))")
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button { tracker.resumeRide() } label: {
                    Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Button { tracker.endRide() } label: {
                    Label("End", systemImage: "flag.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding()
    }

    // MARK: - Sheets

    private var caughtSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 70))
                .foregroundStyle(.red)
            Text("CAUGHT!").font(.largeTitle.bold()).foregroundStyle(.red)
            Text("The \(tracker.chaser?.name ?? "chaser") got you.\nIt let you go… this time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                showCaught = false
                tracker.resumeRide()
            } label: {
                Text("Keep riding").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            Button {
                showCaught = false
                tracker.endRide()
            } label: {
                Text("End ride").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(30)
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var summarySheet: some View {
        if let ride = finishedRide {
            NavigationStack {
                VStack(spacing: 16) {
                    if let chase = ride.chase {
                        Label(chase == .escaped ? "ESCAPED!" : "CAUGHT",
                              systemImage: chase == .escaped ? "trophy.fill" : "exclamationmark.triangle.fill")
                            .font(.title.bold())
                            .foregroundStyle(chase == .escaped ? .green : .red)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        summaryStat("Distance", Format.distance(ride.distance, mph: tracker.useMph))
                        summaryStat("Time", Format.time(ride.duration))
                        summaryStat("Top speed", Format.speed(ride.maxSpeed, mph: tracker.useMph))
                        summaryStat("Climbing", "\(Int(ride.elevationGain)) m")
                    }
                    if !tracker.justUnlocked.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ROUTE UNLOCKED").font(.caption.bold()).foregroundStyle(.purple)
                            ForEach(tracker.justUnlocked) { r in
                                HStack {
                                    Image(systemName: r.icon)
                                    Text("\(r.name) — \(r.tagline)").font(.subheadline)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.purple.opacity(0.12))
                        .cornerRadius(14)
                    }
                    TextField("Add a note…", text: $noteText)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        if !noteText.isEmpty { tracker.updateNote(for: ride.id, note: noteText) }
                        noteText = ""
                        showSummary = false
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding()
                .navigationTitle("Ride complete")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
        }
    }

    private func summaryStat(_ title: String, _ value: String) -> some View {
        VStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(12)
    }
}

// MARK: - Chase setup

struct ChaseSetupView: View {
    @EnvironmentObject var tracker: RideTracker
    @Environment(\.dismiss) var dismiss
    @State private var address = ""
    @State private var selectedChaser: ChaserKind = ChaserKind.all[0]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Enter a destination. Your escape route sticks to pedestrian paths — tight alleys, trails, and cut-throughs cars can't follow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Destination address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                Text("WHO'S CHASING YOU")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(ChaserKind.all) { kind in
                    Button { selectedChaser = kind } label: {
                        HStack {
                            Image(systemName: kind.icon)
                                .font(.title2)
                                .frame(width: 36)
                            VStack(alignment: .leading) {
                                Text(kind.name).font(.headline)
                                Text(kind.blurb).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedChaser.id == kind.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding()
                        .background(selectedChaser.id == kind.id
                                    ? Color.red.opacity(0.15)
                                    : Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                if let err = tracker.routeError {
                    Text(err).foregroundStyle(.red).font(.subheadline)
                }
                Button {
                    tracker.startChase(to: address, chaser: selectedChaser)
                } label: {
                    if tracker.isPreparingChase {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("START CHASE").font(.title2.bold()).frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || tracker.isPreparingChase)
                Spacer()
            }
            .padding()
            .navigationTitle("Chase Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: tracker.state) { _, s in
            if s == .riding { dismiss() }
        }
    }
}
