import Foundation
import CoreLocation

/// Die eine Stelle, an der entschieden wird, woher die Daten kommen.
/// In Berlin/Brandenburg zuerst der VBB (bessere Live-Daten), sonst und als Ersatz Transitous.
enum Fahrplan {
    static let jwdMeter: Double = 5000

    static func haltestellen(bei ort: CLLocationCoordinate2D) async throws -> [Haltestelle] {
        var roh: [Haltestelle] = []
        if VBB.zustaendig(fuer: ort) {
            roh = (try? await VBB.haltestellen(bei: ort)) ?? []
        }
        if roh.isEmpty {
            roh = try await Transitous.haltestellen(bei: ort)
        }
        return ordnen(roh, um: ort)
    }

    /// Nach Entfernung sortieren und Teile desselben Bahnhofs zusammenlegen.
    static func ordnen(_ roh: [Haltestelle], um ort: CLLocationCoordinate2D) -> [Haltestelle] {
        let hier = CLLocation(latitude: ort.latitude, longitude: ort.longitude)
        let sortiert = roh.sorted { $0.ort.distance(from: hier) < $1.ort.distance(from: hier) }
        var ergebnis: [Haltestelle] = []
        for h in sortiert {
            let kern = Namen.kern(h.name)
            let doppelt = ergebnis.contains { e in
                let k = Namen.kern(e.name)
                return (k == kern || kern.hasPrefix(k) || k.hasPrefix(kern)) && e.ort.distance(from: h.ort) < 500
            }
            if !doppelt { ergebnis.append(h) }
            if ergebnis.count == 6 { break }
        }
        return ergebnis
    }

    struct Seite {
        var abfahrten: [Abfahrt]
        var weiter: Weiter?
    }

    enum Weiter {
        case cursor(String)
        case ab(Date)
    }

    static func abfahrten(_ halt: Haltestelle, weiter: Weiter? = nil) async throws -> Seite {
        switch halt.quelle {
        case .vbb:
            var ab: Date?
            if case .ab(let d) = weiter { ab = d }
            let liste = try await VBB.abfahrten(halt, ab: ab)
            let sortiert = liste.sorted { $0.zeit < $1.zeit }
            return Seite(abfahrten: sortiert, weiter: sortiert.last.map { .ab($0.geplant.addingTimeInterval(60)) })
        case .transitous:
            var cursor: String?
            if case .cursor(let c) = weiter { cursor = c }
            let s = try await Transitous.abfahrten(halt, weiter: cursor)
            return Seite(abfahrten: s.abfahrten, weiter: s.weiter.map { .cursor($0) })
        }
    }

    static func verlauf(_ a: Abfahrt) async throws -> [Zwischenhalt] {
        switch a.quelle {
        case .vbb: return try await VBB.verlauf(fahrt: a.fahrtID, ab: a.halt)
        case .transitous: return try await Transitous.verlauf(fahrt: a.fahrtID, ab: a.halt)
        }
    }

    /// Gehzeit zur Haltestelle: Luftlinie mal 1,3 für Umwege, 4,5 km/h.
    static func gehzeit(von ort: CLLocation?, zu halt: Haltestelle) -> TimeInterval {
        guard let ort else { return 0 }
        return ort.distance(from: halt.ort) * 1.3 / 1.25
    }

    /// Abfahrten zusammenführen, Doppeltes weglassen.
    static func zusammen(_ alt: [Abfahrt], _ neu: [Abfahrt]) -> [Abfahrt] {
        var gesehen = Set(alt.map(\.id))
        return alt + neu.filter { gesehen.insert($0.id).inserted }
    }
}
