import Foundation
import CoreLocation

/// Die eine Stelle, an der entschieden wird, woher die Daten kommen.
/// In Berlin/Brandenburg zuerst der VBB (bessere Live-Daten), sonst und als Ersatz Transitous.
enum Fahrplan {
    static let jwdMeter: Double = 5000

    static func haltestellen(bei ort: CLLocationCoordinate2D) async throws -> [Haltestelle] {
        let hier = CLLocation(latitude: ort.latitude, longitude: ort.longitude)
        return auswaehlen(try await kandidaten(bei: ort)) { gehzeit(von: hier, zu: $0) }
    }

    /// Alle Haltestellen der Umgebung, Teile desselben Bahnhofs zusammengelegt, nach Luftlinie sortiert.
    static func kandidaten(bei ort: CLLocationCoordinate2D) async throws -> [Haltestelle] {
        var roh: [Haltestelle] = []
        if VBB.zustaendig(fuer: ort) {
            roh = (try? await VBB.haltestellen(bei: ort)) ?? []
        }
        if roh.isEmpty {
            roh = try await Transitous.haltestellen(bei: ort)
        }
        let hier = CLLocation(latitude: ort.latitude, longitude: ort.longitude)
        let abstand = { (h: Haltestelle) in h.ort.distance(from: hier) }
        var alle: [Haltestelle] = []
        for h in roh.sorted(by: { abstand($0) < abstand($1) }) {
            let kern = Namen.kern(h.name)
            if let i = alle.firstIndex(where: { e in
                let k = Namen.kern(e.name)
                return (k == kern || kern.hasPrefix(k) || k.hasPrefix(kern)) && e.ort.distance(from: h.ort) < 500
            }) {
                // Teil desselben Bahnhofs oder die Haltestelle der Gegenrichtung: Linien übernehmen.
                alle[i].mittel = Array(Set(alle[i].mittel + h.mittel))
                alle[i].linien = Array(Set(alle[i].linien + h.linien))
            } else {
                alle.append(h)
            }
        }
        return alle
    }

    /// Welche Haltestellen zur Auswahl stehen, gemessen in Minuten Fußweg: immer die nächste.
    /// Weitere nur, wenn dort etwas fährt, das es näher nicht gibt – erst bis 6 Minuten, dann Bahnen bis 30,
    /// dann Busse bis 15 Minuten. Bei gleichem Angebot gewinnt der kürzere Weg. Höchstens vier Haltestellen.
    static func auswaehlen(_ alle: [Haltestelle], gehzeit: (Haltestelle) -> TimeInterval) -> [Haltestelle] {
        let sortiert = alle.sorted { gehzeit($0) < gehzeit($1) }
        guard let naechste = sortiert.first else { return [] }

        // Zum Vergleich: Linien, sonst (bei Transitous) Verkehrsmittel.
        func angebot(_ h: Haltestelle) -> Set<String> {
            h.linien.isEmpty ? Set(h.mittel.map { "\($0.rawValue):" }) : Set(h.linien)
        }
        func istBus(_ eintrag: String) -> Bool { eintrag.hasPrefix("bus:") || eintrag.hasPrefix("sonst:") }

        var auswahl = [naechste]
        let durchgaenge: [(TimeInterval, (Set<String>) -> Bool)] = [
            (6 * 60, { !$0.isEmpty }),
            (30 * 60, { $0.contains { !istBus($0) } }),
            (15 * 60, { !$0.isEmpty }),
        ]
        for (minuten, lohntSich) in durchgaenge {
            for h in sortiert where auswahl.count < 4 && !auswahl.contains(h) && gehzeit(h) <= minuten {
                let bekannt = auswahl.reduce(into: Set<String>()) { $0.formUnion(angebot($1)) }
                if lohntSich(angebot(h).subtracting(bekannt)) { auswahl.append(h) }
            }
        }
        return auswahl.sorted { gehzeit($0) < gehzeit($1) }
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

    /// Gehzeit zur Haltestelle nach Luftlinie: mal 1,3 für Umwege, 4,5 km/h. Ersatz, wenn kein echter Fußweg bekannt ist.
    static func gehzeit(von ort: CLLocation?, zu halt: Haltestelle) -> TimeInterval {
        guard let ort else { return 0 }
        return ort.distance(from: halt.ort) * 1.3 / 1.25
    }
}
