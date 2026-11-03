import Foundation
import MapKit

/// Echte Fußwege, berechnet von Apple Karten – dieselbe Quelle, die sich beim Tipp auf den Haltestellennamen öffnet.
/// Luftlinie kennt keine Seen und keine Brücken; Apple Karten schon (so gut die Karte eben ist).
enum Gehwege {
    /// Gehzeit in Sekunden je Haltestelle. Was nicht innerhalb der Frist beantwortet ist, fehlt – dann gilt die Luftlinie.
    static func zeiten(von start: CLLocation, zu halte: [Haltestelle], frist: Double = 8) async -> [String: TimeInterval] {
        await withTaskGroup(of: [String: TimeInterval]?.self) { rennen in
            rennen.addTask { await alle(von: start, zu: halte) }
            rennen.addTask {
                try? await Task.sleep(for: .seconds(frist))
                return nil
            }
            let erstes = await rennen.next() ?? nil
            rennen.cancelAll()
            return erstes ?? [:]
        }
    }

    private static func alle(von start: CLLocation, zu halte: [Haltestelle]) async -> [String: TimeInterval] {
        await withTaskGroup(of: (String, TimeInterval?).self) { gruppe in
            for h in halte {
                gruppe.addTask {
                    let anfrage = MKDirections.Request()
                    anfrage.source = MKMapItem(location: start, address: nil)
                    anfrage.destination = MKMapItem(location: h.ort, address: nil)
                    anfrage.transportType = .walking
                    let eta = try? await MKDirections(request: anfrage).calculateETA()
                    return (h.id, eta?.expectedTravelTime)
                }
            }
            var ergebnis: [String: TimeInterval] = [:]
            for await (id, zeit) in gruppe {
                if let zeit { ergebnis[id] = zeit }
            }
            return ergebnis
        }
    }

    /// Für welche Haltestellen sich das Nachfragen lohnt: die nahen und die Bahnhöfe in der weiteren Umgebung.
    /// Apple begrenzt die Zahl der Anfragen, deshalb höchstens 16.
    /// Was keine 150 m entfernt ist, bleibt bei der Luftlinie: Da steht man praktisch schon – und große Bahnhöfe
    /// liegen in den Daten mitten auf den Gleisen, Apple Karten führt dann zu einer Straße auf der anderen Seite
    /// (am Potsdamer Hauptbahnhof 11 Minuten für 59 m).
    static func auswahl(_ alle: [Haltestelle], um ort: CLLocation) -> [Haltestelle] {
        let alle = alle.filter { $0.ort.distance(from: ort) > 150 }
        let nah = alle.filter { $0.ort.distance(from: ort) <= 700 }.prefix(8)
        let bahn = alle.filter { h in
            h.ort.distance(from: ort) <= 2500 && h.mittel.contains { $0 != .bus && $0 != .sonst }
        }.prefix(8)
        var gesehen = Set<String>()
        return (Array(nah) + Array(bahn)).filter { gesehen.insert($0.id).inserted }
    }
}
