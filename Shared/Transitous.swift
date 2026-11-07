import Foundation
import CoreLocation

/// Freier Fahrplandienst für ganz Deutschland (und darüber hinaus): https://transitous.org
enum Transitous {
    static let basis = "https://api.transitous.org/api"

    static func mittel(_ s: String?) -> Verkehrsmittel {
        switch s ?? "" {
        case "HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL": return .fern
        case "REGIONAL_FAST_RAIL", "REGIONAL_RAIL", "RAIL": return .regio
        case "SUBURBAN": return .sbahn
        case "SUBWAY", "METRO": return .ubahn
        case "TRAM", "CABLE_CAR", "FUNICULAR": return .tram
        case "BUS", "COACH": return .bus
        case "FERRY": return .faehre
        default: return .sonst
        }
    }

    static func linie(_ d: [String: Any]) -> Linie {
        let m = mittel(d.text("mode"))
        let name = d.text("displayName") ?? d.text("routeShortName") ?? d.text("tripShortName") ?? "?"
        return Linie(name: name, mittel: m, farbe: d.text("routeColor"))
    }

    // MARK: Haltestellen in der Nähe

    static func haltestellen(bei ort: CLLocationCoordinate2D) async throws -> [Haltestelle] {
        let j = try await Netz.json(basis, "/v1/reverse-geocode", [
            "place": "\(ort.latitude),\(ort.longitude)",
            "type": "STOP",
        ])
        let nah = ((j as? [[String: Any]]) ?? []).compactMap(haltestelle)
        // Die Umkreissuche reicht nur etwa einen Kilometer weit. Für Bahnhöfe etwas weiter weg
        // und auf dem Land im Kartenausschnitt suchen, notfalls großzügig.
        for spanne in [0.018, 0.06, 0.3] {
            let weit = (try? await imAusschnitt(um: ort, spanne: spanne)) ?? []
            if !weit.isEmpty || !nah.isEmpty { return nah + weit }
        }
        return nah
    }

    private static func haltestelle(_ d: [String: Any]) -> Haltestelle? {
        guard let id = d.text("id") ?? d.text("stopId"), let name = d.text("name"),
              let b = d.zahl("lat"), let l = d.zahl("lon") else { return nil }
        let modi = (d["modes"] as? [String] ?? []).map(mittel)
        return Haltestelle(id: d.text("parentId") ?? id, name: name, breite: b, laenge: l, quelle: .transitous,
                           mittel: Array(Set(modi)))
    }

    private static func imAusschnitt(um o: CLLocationCoordinate2D, spanne: Double) async throws -> [Haltestelle] {
        let breit = spanne * 1.6
        let j = try await Netz.json(basis, "/v1/map/stops", [
            "min": "\(o.latitude - spanne),\(o.longitude - breit)",
            "max": "\(o.latitude + spanne),\(o.longitude + breit)",
        ])
        let hier = CLLocation(latitude: o.latitude, longitude: o.longitude)
        let alle = ((j as? [[String: Any]]) ?? []).compactMap(haltestelle)
            .sorted { $0.ort.distance(from: hier) < $1.ort.distance(from: hier) }
        // Teile desselben Halts zusammenführen, ihre Verkehrsmittel dabei sammeln.
        var nachName: [String: Haltestelle] = [:]
        var reihenfolge: [String] = []
        for h in alle {
            let k = Namen.kern(h.name)
            if var da = nachName[k] {
                da.mittel = Array(Set(da.mittel + h.mittel))
                nachName[k] = da
            } else {
                nachName[k] = h
                reihenfolge.append(k)
            }
        }
        return reihenfolge.prefix(40).compactMap { nachName[$0] }
    }

    // MARK: Abfahrten

    struct Seite {
        var abfahrten: [Abfahrt]
        var weiter: String?
    }

    static func abfahrten(_ halt: Haltestelle, weiter: String? = nil) async throws -> Seite {
        let j = try await Netz.json(basis, "/v5/stoptimes", [
            "stopId": halt.id,
            "n": "40",
            "pageCursor": weiter,
            "withAlerts": "false",
        ]) as? [String: Any] ?? [:]
        var gesehen = Set<String>()
        var ergebnis: [Abfahrt] = []
        for d in j.liste("stopTimes") {
            guard let platz = d.objekt("place"),
                  let geplant = platz.datum("scheduledDeparture") else { continue }
            let linie = linie(d)
            let richtung = d.text("headsign") ?? d.objekt("tripTo")?.text("name") ?? ""
            // Dieselbe Fahrt steckt manchmal in zwei Datensätzen (bundesweit und VBB).
            let schluessel = "\(linie.name)|\(Namen.kern(richtung))|\(geplant.timeIntervalSince1970)"
            guard gesehen.insert(schluessel).inserted else { continue }
            let echt = d.wahr("realTime") ? platz.datum("departure") : nil
            ergebnis.append(Abfahrt(
                id: (d.text("tripId") ?? UUID().uuidString) + (platz.text("stopId") ?? ""),
                linie: linie,
                richtung: richtung,
                geplant: geplant,
                echt: echt,
                gleis: linie.mittel.istZug || linie.mittel == .sbahn ? platz.text("track") : nil,
                faelltAus: d.wahr("cancelled") || d.wahr("tripCancelled") || platz.wahr("cancelled"),
                fahrtID: d.text("tripId") ?? "",
                quelle: .transitous,
                halt: platz.text("name") ?? halt.name
            ))
        }
        return Seite(abfahrten: ergebnis, weiter: j.text("nextPageCursor"))
    }

    // MARK: Fahrtverlauf

    static func verlauf(fahrt: String, ab halt: String) async throws -> [Zwischenhalt] {
        let j = try await Netz.json(basis, "/v5/trip", ["tripId": fahrt]) as? [String: Any] ?? [:]
        guard let abschnitt = j.liste("legs").first(where: { $0.text("mode") != "WALK" }) else { return [] }
        var halte: [[String: Any]] = []
        if let von = abschnitt.objekt("from") { halte.append(von) }
        halte += abschnitt.liste("intermediateStops")
        if let nach = abschnitt.objekt("to") { halte.append(nach) }
        let alle = halte.enumerated().map { i, h in
            Zwischenhalt(
                id: i,
                name: h.text("name") ?? "",
                geplant: h.datum("scheduledDeparture") ?? h.datum("scheduledArrival"),
                echt: h.datum("departure") ?? h.datum("arrival"),
                faelltAus: h.wahr("cancelled")
            )
        }
        let kern = Namen.kern(halt)
        if let start = alle.firstIndex(where: { Namen.kern($0.name).hasPrefix(kern) || kern.hasPrefix(Namen.kern($0.name)) }) {
            return Array(alle[start...])
        }
        return alle
    }

    /// Alle Halte einer Fahrt mit geplanten und – falls bekannt – tatsächlichen Zeiten.
    struct HaltZeit {
        var name: String
        var anGeplant: Date?
        var an: Date?
        var abGeplant: Date?
        var ab: Date?
        var gleis: String?
        var faelltAus: Bool
    }

    static func halte(fahrt: String) async throws -> [HaltZeit] {
        let j = try await Netz.json(basis, "/v5/trip", ["tripId": fahrt]) as? [String: Any] ?? [:]
        guard let l = j.liste("legs").first(where: { $0.text("mode") != "WALK" }) else { return [] }
        let echt = l.wahr("realTime")
        let weg = l.wahr("cancelled") || l.wahr("tripCancelled")
        var roh: [[String: Any]] = []
        if let von = l.objekt("from") { roh.append(von) }
        roh += l.liste("intermediateStops")
        if let nach = l.objekt("to") { roh.append(nach) }
        return roh.map { h in
            HaltZeit(
                name: h.text("name") ?? "",
                anGeplant: h.datum("scheduledArrival"),
                an: echt ? h.datum("arrival") : nil,
                abGeplant: h.datum("scheduledDeparture"),
                ab: echt ? h.datum("departure") : nil,
                gleis: h.text("track"),
                faelltAus: weg || h.wahr("cancelled")
            )
        }
    }

    // MARK: Ziele suchen

    static func suchen(_ text: String, nahe ort: CLLocationCoordinate2D?) async throws -> [Ziel] {
        let j = try await Netz.json(basis, "/v1/geocode", [
            "text": text,
            "place": ort.map { "\($0.latitude),\($0.longitude)" },
            "language": "de",
        ])
        let hier = ort.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var gesehen = Set<String>()
        let ziele: [(Ziel, Bool)] = ((j as? [[String: Any]]) ?? []).compactMap { d in
            guard let roh = d.text("name"), let b = d.zahl("lat"), let l = d.zahl("lon") else { return nil }
            let typ = d.text("type")
            let gebiet = d.liste("areas").first(where: { $0.wahr("default") })?.text("name")
            var name = typ == "STOP" ? Namen.kurz(roh, ort: gebiet) : roh
            if typ == "ADDRESS", let strasse = d.text("street") {
                name = strasse + (d.text("houseNumber").map { " \($0)" } ?? "")
            }
            guard gesehen.insert(Namen.kern(name) + (gebiet ?? "")).inserted else { return nil }
            let zusatz = gebiet.map { name.contains($0) ? nil : $0 } ?? nil
            let ziel = Ziel(id: d.text("id") ?? roh, name: name, zusatz: zusatz, breite: b, laenge: l,
                            haltID: typ == "STOP" ? d.text("id") : nil)
            let fern = hier.map { CLLocation(latitude: b, longitude: l).distance(from: $0) > 150_000 } ?? false
            return (ziel, fern)
        }
        // Was in der Nähe liegt, zuerst; die Reihenfolge des Dienstes bleibt sonst erhalten.
        return ziele.filter { !$0.1 }.map(\.0) + ziele.filter { $0.1 }.map(\.0)
    }

    // MARK: Verbindungen

    struct Verbindungen {
        var liste: [Verbindung]
        var weiter: String?
    }

    static func verbindungen(von start: CLLocationCoordinate2D, nach ziel: Ziel, ab: Date? = nil,
                             weiter: String? = nil) async throws -> Verbindungen {
        let j = try await Netz.json(basis, "/v5/plan", [
            "fromPlace": "\(start.latitude),\(start.longitude)",
            "toPlace": ziel.anfrage,
            "time": ab.map(Zeit.schreiben),
            "pageCursor": weiter,
            "numItineraries": "6",
            "withFares": "false",
            "detailedTransfers": "false",
        ]) as? [String: Any] ?? [:]
        let liste = j.liste("itineraries").enumerated().map { nr, it in
            Verbindung(
                id: it.text("id") ?? "\(weiter ?? "")\(nr)",
                abschnitte: it.liste("legs").enumerated().compactMap { i, l in abschnitt(l, nr: i, ziel: ziel) }
            )
        }
        let sortiert = liste.filter { !$0.abschnitte.isEmpty }.sorted { ($0.ab, $0.an) < ($1.ab, $1.an) }
        return Verbindungen(liste: sortiert, weiter: j.text("nextPageCursor"))
    }

    private static func abschnitt(_ l: [String: Any], nr: Int, ziel: Ziel) -> Abschnitt? {
        guard let von = l.objekt("from"), let nach = l.objekt("to"),
              let ab = l.datum("scheduledStartTime") ?? l.datum("startTime"),
              let an = l.datum("scheduledEndTime") ?? l.datum("endTime") else { return nil }
        let zuFuss = ["WALK", "BIKE", "CAR"].contains(l.text("mode") ?? "")
        let echt = l.wahr("realTime")
        func name(_ p: [String: Any], _ standard: String) -> String {
            let n = p.text("name") ?? standard
            return n == "START" ? "Hier" : (n == "END" ? ziel.name : n)
        }
        return Abschnitt(
            id: nr,
            linie: zuFuss ? nil : linie(l),
            richtung: l.text("headsign") ?? "",
            von: name(von, "Hier"),
            nach: name(nach, ziel.name),
            abGeplant: ab,
            abEcht: echt ? l.datum("startTime") : nil,
            anGeplant: an,
            anEcht: echt ? l.datum("endTime") : nil,
            gleis: zuFuss ? nil : von.text("track"),
            meter: l.zahl("distance"),
            fahrtID: l.text("tripId"),
            zwischenhalte: l.liste("intermediateStops").enumerated().map { i, h in
                Zwischenhalt(id: i, name: h.text("name") ?? "",
                             geplant: h.datum("scheduledDeparture") ?? h.datum("scheduledArrival"),
                             echt: echt ? (h.datum("departure") ?? h.datum("arrival")) : nil)
            }
        )
    }
}
