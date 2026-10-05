import Foundation
import CoreLocation
import MapKit

enum RideState {
    case idle, riding, paused
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

@MainActor
final class RideTracker: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published state
    @Published var state: RideState = .idle
    @Published var points: [RidePoint] = []
    @Published var currentSpeed: Double = 0
    @Published var elapsed: TimeInterval = 0
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var rides: [Ride] = []

    // Chase mode
    @Published var chaser: ChaserKind? = nil
    @Published var chaserCoord: CLLocationCoordinate2D? = nil
    @Published var chaserDistance: Double? = nil
    @Published var caught: Bool = false

    // Escape destination (chase mode)
    @Published var destination: CLLocationCoordinate2D? = nil
    @Published var destinationName: String? = nil
    @Published var escapeRouteCoords: [CLLocationCoordinate2D] = []
    @Published var distanceToDestination: Double? = nil
    @Published var routeError: String? = nil
    @Published var isPreparingChase = false
    @Published var completedRide: Ride? = nil

    // Lifetime stats
    @Published var totalDistance: Double = 0
    @Published var totalRides: Int = 0
    @Published var totalTime: TimeInterval = 0
    @Published var topSpeed: Double = 0
    @Published var unlockedRoutes: Set<String> = []
    @Published var justUnlocked: [HiddenRoute] = []
    @Published var useMph: Bool = false

    var pendingRouteTag: String? = nil

    // MARK: - Private
    private let manager = CLLocationManager()
    private let defaults = UserDefaults.standard
    private var startDate: Date?
    private var pauseAccum: TimeInterval = 0
    private var pauseStart: Date?
    private var timer: Timer?
    private var lastChaserUpdate: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        rides = RideStore.load()
        loadStats()
    }

    // MARK: - Permissions

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    // MARK: - Ride control

    func startRide(chaser: ChaserKind?, routeTag: String?) {
        points = []
        self.chaser = chaser
        self.pendingRouteTag = routeTag
        caught = false
        chaserCoord = nil
        chaserDistance = nil
        lastChaserUpdate = nil
        completedRide = nil
        justUnlocked = []
        startDate = Date()
        pauseAccum = 0
        pauseStart = nil
        elapsed = 0
        currentSpeed = 0
        state = .riding
        manager.startUpdatingLocation()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    /// Chase mode: geocode the destination, fetch a walking escape route
    /// (pedestrian paths — the tight spots cars can't follow), then start.
    func startChase(to address: String, chaser: ChaserKind) {
        isPreparingChase = true
        routeError = nil
        CLGeocoder().geocodeAddressString(address) { [weak self] placemarks, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let place = placemarks?.first,
                      let coord = place.location?.coordinate else {
                    self.isPreparingChase = false
                    self.routeError = "Couldn't find that address. Try another."
                    return
                }
                self.destination = coord
                self.destinationName = place.name ?? address
                self.fetchEscapeRoute(to: coord, chaser: chaser)
            }
        }
    }

    private func fetchEscapeRoute(to coord: CLLocationCoordinate2D, chaser: ChaserKind) {
        let request = MKDirections.Request()
        request.source = .forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        request.transportType = .walking
        MKDirections(request: request).calculate { [weak self] response, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPreparingChase = false
                guard let route = response?.routes.first else {
                    self.routeError = "No route found. Try another address."
                    self.destination = nil
                    self.destinationName = nil
                    return
                }
                self.escapeRouteCoords = route.polyline.coordinates
                self.startRide(chaser: chaser, routeTag: nil)
            }
        }
    }

    private func clearRouteState() {
        destination = nil
        destinationName = nil
        escapeRouteCoords = []
        distanceToDestination = nil
        routeError = nil
    }

    func pauseRide() {
        guard state == .riding else { return }
        state = .paused
        pauseStart = Date()
    }

    func resumeRide() {
        guard state == .paused else { return }
        if let ps = pauseStart { pauseAccum += Date().timeIntervalSince(ps) }
        pauseStart = nil
        if caught {
            // the chaser got bored and wandered off
            caught = false
            chaserCoord = nil
            chaserDistance = nil
            lastChaserUpdate = nil
        }
        state = .riding
    }

    @discardableResult
    func endRide() -> Ride? {
        guard state != .idle, let start = startDate else { return nil }
        manager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        let result: ChaseResult? = chaser == nil ? nil : (caught ? .caught : .escaped)
        let ride = Ride(id: UUID(), startDate: start, endDate: Date(), points: points,
                        chase: result, chaserName: chaser?.name, routeTag: pendingRouteTag)
        rides.insert(ride, at: 0)
        RideStore.save(rides)
        recordStats(ride)
        checkUnlocks(ride: ride)
        state = .idle
        chaser = nil
        caught = false
        chaserCoord = nil
        chaserDistance = nil
        pendingRouteTag = nil
        clearRouteState()
        completedRide = ride
        return ride
    }

    func deleteRide(_ ride: Ride) {
        rides.removeAll { $0.id == ride.id }
        RideStore.save(rides)
        recomputeStats()
    }

    func updateNote(for rideID: UUID, note: String) {
        if let i = rides.firstIndex(where: { $0.id == rideID }) {
            rides[i].note = note
            RideStore.save(rides)
        }
    }

    func resetAll() {
        rides = []
        RideStore.save(rides)
        totalDistance = 0
        totalRides = 0
        totalTime = 0
        topSpeed = 0
        unlockedRoutes = []
        saveStats()
    }

    func toggleUnits() {
        useMph.toggle()
        saveStats()
    }

    // MARK: - Derived values

    var currentDistance: Double {
        guard points.count > 1 else { return 0 }
        var d = 0.0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i - 1].lat, longitude: points[i - 1].lon)
            let b = CLLocation(latitude: points[i].lat, longitude: points[i].lon)
            d += a.distance(from: b)
        }
        return d
    }

    var currentAvgSpeed: Double { elapsed > 0 ? currentDistance / elapsed : 0 }
    var currentMaxSpeed: Double { points.map(\.speed).max() ?? 0 }

    // MARK: - Private helpers

    private func tick() {
        guard state == .riding, let start = startDate else { return }
        elapsed = Date().timeIntervalSince(start) - pauseAccum
    }

    private func updateChaser(at loc: CLLocation) {
        guard let kind = chaser, !caught else { return }
        let now = Date()
        if chaserCoord == nil {
            // spawns ~280 m south of you. run.
            chaserCoord = CLLocationCoordinate2D(latitude: loc.coordinate.latitude - 0.0025,
                                                 longitude: loc.coordinate.longitude)
            lastChaserUpdate = now
            chaserDistance = 280
            return
        }
        let dt = now.timeIntervalSince(lastChaserUpdate ?? now)
        lastChaserUpdate = now
        guard dt > 0 else { return }
        let avg = elapsed > 5 ? currentAvgSpeed : max(currentSpeed, 3)
        let speed = max(4.0, avg * kind.speedFactor)
        let step = speed * dt
        let cc = chaserCoord!
        let from = CLLocation(latitude: cc.latitude, longitude: cc.longitude)
        let dist = from.distance(from: loc)
        if dist - step <= 25 {
            chaserDistance = dist
            caught = true
            pauseRide()
            return
        }
        let f = step / dist
        chaserCoord = CLLocationCoordinate2D(
            latitude: cc.latitude + (loc.coordinate.latitude - cc.latitude) * f,
            longitude: cc.longitude + (loc.coordinate.longitude - cc.longitude) * f)
        chaserDistance = dist - step
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard state == .riding, let loc = locations.last else { return }
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 65 else { return }
        let spd = loc.speed >= 0 ? loc.speed : 0
        currentSpeed = spd
        points.append(RidePoint(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                                timestamp: loc.timestamp, speed: spd, altitude: loc.altitude))
        // escape check: reached the destination?
        if let dest = destination, state == .riding {
            let d = CLLocation(latitude: dest.latitude, longitude: dest.longitude).distance(from: loc)
            distanceToDestination = d
            if d < 50 {
                endRide() // completedRide is set -> summary shows ESCAPED
                return
            }
        }
        updateChaser(at: loc)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // transient GPS errors are ignored; the next fix will come in
    }

    // MARK: - Stats

    private func recordStats(_ ride: Ride) {
        totalDistance += ride.distance
        totalRides += 1
        totalTime += ride.duration
        topSpeed = max(topSpeed, ride.maxSpeed)
        saveStats()
    }

    private func recomputeStats() {
        totalDistance = rides.reduce(0) { $0 + $1.distance }
        totalRides = rides.count
        totalTime = rides.reduce(0) { $0 + $1.duration }
        topSpeed = rides.map(\.maxSpeed).max() ?? 0
        saveStats()
    }

    private func checkUnlocks(ride: Ride) {
        for route in HiddenRoute.all where !unlockedRoutes.contains(route.id) {
            if route.requirement.isMet(by: ride, totalDistance: totalDistance, totalRides: totalRides) {
                unlockedRoutes.insert(route.id)
                justUnlocked.append(route)
            }
        }
        saveStats()
    }

    private func saveStats() {
        defaults.set(totalDistance, forKey: "tt.totalDistance")
        defaults.set(totalRides, forKey: "tt.totalRides")
        defaults.set(totalTime, forKey: "tt.totalTime")
        defaults.set(topSpeed, forKey: "tt.topSpeed")
        defaults.set(Array(unlockedRoutes), forKey: "tt.unlockedRoutes")
        defaults.set(useMph, forKey: "tt.useMph")
    }

    private func loadStats() {
        totalDistance = defaults.double(forKey: "tt.totalDistance")
        totalRides = defaults.integer(forKey: "tt.totalRides")
        totalTime = defaults.double(forKey: "tt.totalTime")
        topSpeed = defaults.double(forKey: "tt.topSpeed")
        unlockedRoutes = Set(defaults.stringArray(forKey: "tt.unlockedRoutes") ?? [])
        useMph = defaults.bool(forKey: "tt.useMph")
    }
}
