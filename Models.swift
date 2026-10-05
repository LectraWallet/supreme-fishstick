import Foundation
import CoreLocation

// MARK: - Ride data

struct RidePoint: Codable {
    var lat: Double
    var lon: Double
    var timestamp: Date
    var speed: Double      // m/s
    var altitude: Double   // m
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

enum ChaseResult: String, Codable {
    case escaped, caught
}

struct Ride: Codable, Identifiable, Equatable {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var points: [RidePoint]
    var chase: ChaseResult?
    var chaserName: String?
    var routeTag: String?
    var note: String = ""

    var distance: Double {
        guard points.count > 1 else { return 0 }
        var d = 0.0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i - 1].lat, longitude: points[i - 1].lon)
            let b = CLLocation(latitude: points[i].lat, longitude: points[i].lon)
            d += a.distance(from: b)
        }
        return d
    }

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
    var maxSpeed: Double { points.map(\.speed).max() ?? 0 }
    var avgSpeed: Double { duration > 0 ? distance / duration : 0 }

    var elevationGain: Double {
        var g = 0.0
        for i in 1..<points.count {
            let d = points[i].altitude - points[i - 1].altitude
            if d > 0 { g += d }
        }
        return g
    }
}

// MARK: - Persistence

enum RideStore {
    static func fileURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rides.json")
    }

    static func load() -> [Ride] {
        guard let data = try? Data(contentsOf: fileURL()) else { return [] }
        return (try? JSONDecoder().decode([Ride].self, from: data)) ?? []
    }

    static func save(_ rides: [Ride]) {
        try? JSONEncoder().encode(rides).write(to: fileURL())
    }
}

enum GPXExporter {
    static func gpx(for ride: Ride) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        s += "<gpx version=\"1.1\" creator=\"TalariaTracker\">\n<trk><name>Talaria Ride</name><trkseg>\n"
        let f = ISO8601DateFormatter()
        for p in ride.points {
            s += "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><ele>\(p.altitude)</ele><time>\(f.string(from: p.timestamp))</time></trkpt>\n"
        }
        s += "</trkseg></trk>\n</gpx>\n"
        return s
    }
}

// MARK: - Chasers

struct ChaserKind: Identifiable, Hashable {
    var id: String
    var name: String
    var icon: String        // SF Symbol, no emojis
    var speedFactor: Double   // fraction of your average speed
    var blurb: String

    static let all: [ChaserKind] = [
        ChaserKind(id: "horde", name: "The Horde", icon: "figure.run", speedFactor: 0.80,
                   blurb: "Slow but relentless. Don't you dare stop."),
        ChaserKind(id: "rival", name: "Rival Rider", icon: "bicycle", speedFactor: 0.95,
                   blurb: "Nearly as fast as you. Spicy."),
        ChaserKind(id: "ranger", name: "Ranger Rick", icon: "shield.fill", speedFactor: 0.65,
                   blurb: "He just wants to talk about your fender."),
    ]
}

// MARK: - Hidden routes

enum RouteRequirement {
    case nightRide
    case topSpeedKmh(Double)
    case totalKm(Double)
    case rideCount(Int)

    var hint: String {
        switch self {
        case .nightRide: return "Finish a ride after 10 PM…"
        case .topSpeedKmh(let v): return "Hit \(Int(v)) km/h on a ride…"
        case .totalKm(let v): return "Ride \(Int(v)) km in total…"
        case .rideCount(let n): return "Complete \(n) rides…"
        }
    }

    func isMet(by ride: Ride, totalDistance: Double, totalRides: Int) -> Bool {
        switch self {
        case .nightRide:
            let h = Calendar.current.component(.hour, from: ride.startDate)
            return h >= 22 || h < 5
        case .topSpeedKmh(let v):
            return ride.maxSpeed >= v / 3.6
        case .totalKm(let v):
            return totalDistance >= v * 1000
        case .rideCount(let n):
            return totalRides >= n
        }
    }

    func progress(totalDistance: Double, totalRides: Int, topSpeed: Double) -> Double {
        switch self {
        case .nightRide:
            return 0 // mysterious on purpose
        case .topSpeedKmh(let v):
            return min(1, topSpeed / (v / 3.6))
        case .totalKm(let v):
            return min(1, totalDistance / (v * 1000))
        case .rideCount(let n):
            return min(1, Double(totalRides) / Double(n))
        }
    }
}

struct HiddenRoute: Identifiable {
    let id: String
    let name: String
    let icon: String   // SF Symbol, no emojis
    let tagline: String
    let requirement: RouteRequirement

    static let all: [HiddenRoute] = [
        HiddenRoute(id: "midnight", name: "Midnight Run", icon: "moon.fill",
                    tagline: "The city is quiet. The bike is not.",
                    requirement: .nightRide),
        HiddenRoute(id: "demon", name: "Speed Demon", icon: "bolt.fill",
                    tagline: "Pin it.",
                    requirement: .topSpeedKmh(60)),
        HiddenRoute(id: "century", name: "Century Grind", icon: "map.fill",
                    tagline: "100 km. No excuses.",
                    requirement: .totalKm(100)),
        HiddenRoute(id: "ghost", name: "Ghost Trail", icon: "sparkles",
                    tagline: "Ten rides. You're haunting these streets now.",
                    requirement: .rideCount(10)),
    ]
}

// MARK: - Formatting

enum Format {
    static func speed(_ ms: Double, mph: Bool) -> String {
        if mph { return String(format: "%.0f mph", ms * 2.23694) }
        return String(format: "%.0f km/h", ms * 3.6)
    }

    static func distance(_ m: Double, mph: Bool) -> String {
        if mph { return String(format: "%.2f mi", m / 1609.34) }
        return String(format: "%.2f km", m / 1000)
    }

    static func time(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
