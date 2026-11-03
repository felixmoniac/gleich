import Foundation
import CoreLocation

/// Freie Schnittstelle des Verkehrsverbunds Berlin-Brandenburg: https://v6.vbb.transport.rest
enum VBB {
    static let basis = "https://v6.vbb.transport.rest"

    /// Grob das Verbundgebiet. Liefert der VBB dort nichts, springt Transitous ein.
    static func zustaendig(fuer o: CLLocationCoordinate2D) -> Bool {
        (51.35...53.56).contains(o.latitude) && (11.26...14.77).contains(o.longitude)
    }

    static func mittel(_ produkt: String?) -> Verkehrsmittel {
        switch produkt ?? "" {
        case "express": return .fern
        case "regional": return .regio
        case "suburban": return .sbahn
        case "subway": return .ubahn
        case "tram": return .tram
        case "bus": return .bus
        case "ferry": return .faehre
        default: return .sonst
        }
    }

    static func linie(_ l: [String: Any]?) -> Linie {
        let l = l ?? [:]
        let farbe = l.objekt("color")?.text("bg").map { $0.replacingOccurrences(of: "#", with: "") }
        return Linie(name: l.text("name") ?? "?", mittel: mittel(l.text("product")), farbe: farbe)
    }

    static func haltestellen(bei o: CLLocationCoordinate2D) async throws -> [Haltestelle] {
        let j = try await Netz.json(basis, "/locations/nearby", [
            "latitude": "\(o.latitude)",
            "longitude": "\(o.longitude)",
            "results": "10",
            "distance": "8000",
            "linesOfStops": "false",
        ])
        let liste = (j as? [[String: Any]]) ?? []
        return liste.compactMap { d in
            guard let id = d.text("id"), let name = d.text("name"),
                  let ort = d.objekt("location"),
                  let b = ort.zahl("latitude"), let l = ort.zahl("longitude") else { return nil }
            return Haltestelle(id: id, name: name, breite: b, laenge: l, quelle: .vbb)
        }
    }

    static func abfahrten(_ halt: Haltestelle, ab: Date? = nil) async throws -> [Abfahrt] {
        let erste = try await abfahrten(halt, ab: ab, minuten: 60)
        // Auf dem Land fährt oft stundenlang nichts – dann weiter vorausschauen.
        if erste.isEmpty { return try await abfahrten(halt, ab: ab, minuten: 720) }
        return erste
    }

    private static func abfahrten(_ halt: Haltestelle, ab: Date?, minuten: Int) async throws -> [Abfahrt] {
        let j = try await Netz.json(basis, "/stops/\(halt.id)/departures", [
            "duration": "\(minuten)",
            "results": "60",
            "when": ab.map(Zeit.schreiben),
            "remarks": "false",
        ]) as? [String: Any] ?? [:]
        let kern = Namen.kern(halt.name)
        return j.liste("departures").compactMap { d in
            guard let geplant = d.datum("plannedWhen") else { return nil }
            let teil = d.objekt("stop")?.text("name") ?? halt.name
            // Nur Teile desselben Bahnhofs, nicht die Nachbarhaltestelle um die Ecke.
            guard Namen.kern(teil).hasPrefix(kern) || kern.hasPrefix(Namen.kern(teil)) else { return nil }
            let linie = linie(d.objekt("line"))
            return Abfahrt(
                id: (d.text("tripId") ?? UUID().uuidString) + teil,
                linie: linie,
                richtung: d.text("direction") ?? d.objekt("destination")?.text("name") ?? "",
                geplant: geplant,
                echt: d.datum("when"),
                gleis: linie.mittel.istZug || linie.mittel == .sbahn ? (d.text("platform") ?? d.text("plannedPlatform")) : nil,
                faelltAus: d.wahr("cancelled"),
                fahrtID: d.text("tripId") ?? "",
                quelle: .vbb,
                halt: teil
            )
        }
    }

    static func verlauf(fahrt: String, ab halt: String) async throws -> [Zwischenhalt] {
        let id = fahrt.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? fahrt
        let j = try await Netz.json(basis, "/trips/\(id)", [
            "stopovers": "true",
            "polyline": "false",
            "remarks": "false",
        ]) as? [String: Any] ?? [:]
        let alle = (j.objekt("trip")?.liste("stopovers") ?? []).enumerated().map { i, s in
            Zwischenhalt(
                id: i,
                name: s.objekt("stop")?.text("name") ?? "",
                geplant: s.datum("plannedDeparture") ?? s.datum("plannedArrival"),
                echt: s.datum("departure") ?? s.datum("arrival"),
                faelltAus: s.wahr("cancelled")
            )
        }
        let kern = Namen.kern(halt)
        if let start = alle.firstIndex(where: { Namen.kern($0.name) == kern }) {
            return Array(alle[start...])
        }
        return alle
    }
}
