import Foundation
import CoreLocation
import Observation
import WidgetKit

/// Zustand einer Haltestellen-Seite.
@Observable
final class HaltModell: Identifiable {
    let halt: Haltestelle
    var abfahrten: [Abfahrt]
    var laedt = false
    var ohneNetz = false
    var filter: Verkehrsmittel?

    var id: String { halt.id }

    init(_ halt: Haltestelle) {
        self.halt = halt
        abfahrten = Ablage.lesen([Abfahrt].self, "ab." + halt.id) ?? []
    }

    /// Welche Verkehrsmittel hier fahren – für die Symbolreihe.
    var mittel: [Verkehrsmittel] {
        let da = Set(abfahrten.map(\.linie.mittel))
        return Verkehrsmittel.reihenfolge.filter(da.contains)
    }

    /// Nur die nächsten Abfahrten – eine ruhige, feste Liste ohne Nachladen.
    static let hoechstens = 15

    func sichtbar(jetzt: Date) -> [Abfahrt] {
        Array(abfahrten.filter { a in
            a.zeit.timeIntervalSince(jetzt) > -30 && (filter == nil || a.linie.mittel == filter)
        }.prefix(HaltModell.hoechstens))
    }

    func laden() async {
        laedt = true
        defer { laedt = false }
        do {
            let seite = try await Fahrplan.abfahrten(halt)
            abfahrten = seite.abfahrten
            ohneNetz = false
            if filter.map({ !mittel.contains($0) }) == true { filter = nil }
            Ablage.schreiben(abfahrten, "ab." + halt.id)
        } catch {
            ohneNetz = true
        }
    }
}

/// Alles rund um „Wo bin ich, was fährt hier?“.
@Observable
final class Umgebung {
    let standort = Standort()
    let plaene = Planablage()
    var seiten: [HaltModell] = []
    var seite: String?
    var laedt = false
    var ohneNetz = false
    /// Nächste Haltestelle weiter als 5 km weg.
    var jwd = false
    /// Echte Gehzeiten von Apple Karten (Sekunden je Haltestelle), vom Ort der letzten Haltestellensuche aus.
    private var gehzeiten: [String: TimeInterval] = [:]
    private var ortDerHaltestellen: CLLocation?

    init() {
        if let alt = Ablage.lesen([Haltestelle].self, "haltestellen") {
            seiten = alt.map(HaltModell.init)
            seite = seiten.first?.id
        }
    }

    var aktuell: HaltModell? { seiten.first { $0.id == seite } }

    /// Standort holen, bei Bedarf Haltestellen neu suchen, dann die sichtbare Seite laden.
    func allesNeu() async {
        guard !laedt else { return }
        laedt = true
        defer { laedt = false }
        guard let ort = await standort.frisch() else { return }
        defer { Task { await netzplaene(bei: ort) } }
        let weit = ortDerHaltestellen.map { $0.distance(from: ort) > 120 } ?? true
        if weit || seiten.isEmpty {
            do {
                let alle = try await Fahrplan.kandidaten(bei: ort.coordinate)
                gehzeiten = await Gehwege.zeiten(von: ort, zu: Gehwege.auswahl(alle, um: ort))
                let liste = Fahrplan.auswaehlen(alle) { gehzeit(zu: $0, von: ort) }
                ortDerHaltestellen = ort
                ohneNetz = false
                jwd = (liste.first?.ort.distance(from: ort) ?? .infinity) > Fahrplan.jwdMeter
                if liste.map(\.id) != seiten.map(\.id) {
                    let alt = Dictionary(seiten.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    seiten = liste.map { alt[$0.id] ?? HaltModell($0) }
                    seite = jwd ? "jwd" : seiten.first?.id
                    Ablage.schreiben(liste, "haltestellen")
                }
            } catch {
                ohneNetz = true
            }
        }
        if let a = aktuell {
            await a.laden()
            ohneNetz = a.ohneNetz
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Netzpläne für den Verbund und den Ort, an dem man gerade ist.
    private func netzplaene(bei ort: CLLocation) async {
        var orte: [String] = []
        if let p = try? await CLGeocoder().reverseGeocodeLocation(ort).first {
            if let o = p.locality { orte.append(o) }
        }
        if let o = Namen.ort(unter: seiten.map(\.halt.name)) { orte.append(o) }
        await plaene.aktualisieren(bei: ort.coordinate, orte: Array(Set(orte)).sorted())
    }

    /// Fußweg zur Haltestelle: echt, wenn Apple Karten ihn kennt, sonst nach Luftlinie.
    func gehzeit(zu halt: Haltestelle, von ort: CLLocation? = nil) -> TimeInterval {
        gehzeiten[halt.id] ?? Fahrplan.gehzeit(von: ort ?? standort.ort, zu: halt)
    }

    func erreichbar(_ a: Abfahrt, an halt: Haltestelle, jetzt: Date) -> Bool {
        a.zeit.timeIntervalSince(jetzt) >= gehzeit(zu: halt)
    }
}
