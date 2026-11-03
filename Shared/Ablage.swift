import Foundation
import CoreLocation

/// Gemeinsamer Speicher von App und Widget.
enum Ablage {
    static let gruppe = "group.com.fmoniac.Gleich"
    static var standard: UserDefaults { UserDefaults(suiteName: gruppe) ?? .standard }

    static var letzterOrt: CLLocation? {
        get {
            let d = standard
            guard d.object(forKey: "ort.breite") != nil else { return nil }
            return CLLocation(latitude: d.double(forKey: "ort.breite"), longitude: d.double(forKey: "ort.laenge"))
        }
        set {
            guard let o = newValue else { return }
            standard.set(o.coordinate.latitude, forKey: "ort.breite")
            standard.set(o.coordinate.longitude, forKey: "ort.laenge")
        }
    }

    static func lesen<T: Decodable>(_ typ: T.Type, _ schluessel: String) -> T? {
        guard let d = standard.data(forKey: schluessel) else { return nil }
        return try? JSONDecoder().decode(typ, from: d)
    }

    static func schreiben<T: Encodable>(_ wert: T, _ schluessel: String) {
        if let d = try? JSONEncoder().encode(wert) { standard.set(d, forKey: schluessel) }
    }
}
