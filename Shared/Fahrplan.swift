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

    /// Welche Haltestellen zur Auswahl stehen: immer die nächste. Weitere nur, wenn dort etwas fährt,
    /// das es näher nicht gibt – erst in Gehweite (etwa 5 Minuten), dann Bahnen bis 2 km, dann Busse bis 1 km.
    /// Höchstens vier Haltestellen.
    static func ordnen(_ roh: [Haltestelle], um ort: CLLocationCoordinate2D) -> [Haltestelle] {
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
        guard let naechste = alle.first else { return [] }

        // Zum Vergleich: Linien, sonst (bei Transitous) Verkehrsmittel.
        func angebot(_ h: Haltestelle) -> Set<String> {
            h.linien.isEmpty ? Set(h.mittel.map { "\($0.rawValue):" }) : Set(h.linien)
        }
        func istBus(_ eintrag: String) -> Bool { eintrag.hasPrefix("bus:") || eintrag.hasPrefix("sonst:") }

        var auswahl = [naechste]
        let durchgaenge: [((Haltestelle) -> Bool, (Set<String>) -> Bool)] = [
            ({ gehzeit(von: hier, zu: $0) <= 6 * 60 }, { !$0.isEmpty }),
            ({ abstand($0) <= 2000 }, { $0.contains { !istBus($0) } }),
            ({ abstand($0) <= 1000 }, { !$0.isEmpty }),
        ]
        for (inReichweite, lohntSich) in durchgaenge {
            for h in alle where auswahl.count < 4 && !auswahl.contains(h) && inReichweite(h) {
                let bekannt = auswahl.reduce(into: Set<String>()) { $0.formUnion(angebot($1)) }
                if lohntSich(angebot(h).subtracting(bekannt)) { auswahl.append(h) }
            }
        }
        return auswahl.sorted { abstand($0) < abstand($1) }
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
