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

    /// Nur die nächsten Abfahrten: insgesamt höchstens 15, je Linie höchstens vier, je Richtung höchstens zwei.
    /// Von den blassen (zu Fuß wohl nicht mehr zu schaffen) zählt je Richtung nur eine mit –
    /// sonst stünde dort womöglich nichts, was man noch erreicht.
    static let hoechstens = 15

    func sichtbar(jetzt: Date, erreichbar: (Abfahrt) -> Bool) -> [Abfahrt] {
        var jeLinie: [String: Int] = [:]
        var jeRichtung: [String: (alle: Int, blass: Int)] = [:]
        let auswahl = abfahrten.filter { a in
            guard a.zeit.timeIntervalSince(jetzt) > -30, filter == nil || a.linie.mittel == filter else { return false }
            let linie = a.linie.mittel.rawValue + a.linie.name
            let richtung = linie + "|" + Namen.kern(a.richtung)
            var zaehler = jeRichtung[richtung] ?? (0, 0)
            let blass = !erreichbar(a)
            guard jeLinie[linie, default: 0] < 4, zaehler.alle < 2, !(blass && zaehler.blass >= 1) else { return false }
            zaehler.alle += 1
            if blass { zaehler.blass += 1 }
            jeRichtung[richtung] = zaehler
            jeLinie[linie, default: 0] += 1
            return true
        }
        return Array(auswahl.prefix(HaltModell.hoechstens))
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

/// Was beim letzten Mal in der Nähe war – damit die Haltestellen nach einem Neustart sofort dastehen,
/// wenn man noch am selben Ort ist.
private struct Nahbereich: Codable {
    var breite: Double
    var laenge: Double
    var haltestellen: [Haltestelle]
    var gehzeiten: [String: TimeInterval]
    var ort: CLLocation { CLLocation(latitude: breite, longitude: laenge) }
}

/// Alles rund um „Wo bin ich, was fährt hier?“.
@Observable
final class Umgebung {
    let standort = Standort()
    let plaene = Planablage()
    var seiten: [HaltModell] = []
    /// Die Lok tuckert – bis die Haltestellen dastehen. Die Abfahrten laden danach still weiter.
    var laedt = false
    var ohneNetz = false
    /// Die App war zu: Die Haltestellen bleiben verborgen, bis der neue Standort sagt,
    /// ob sie noch stimmen – sonst stünde in Bochum noch „Feldstraße“. Am selben Ort sind sie sofort wieder da.
    var veraltet = true
    /// Nächste Haltestelle weiter als 5 km weg.
    var jwd = false
    /// Echte Gehzeiten von Apple Karten (Sekunden je Haltestelle), vom Ort der letzten Haltestellensuche aus.
    private var gehzeiten: [String: TimeInterval] = [:]
    private var ortDerHaltestellen: CLLocation?
    /// Läuft gerade ein Durchgang (auch das stille Nachladen der Abfahrten)?
    private var beschaeftigt = false
    /// Kam während des Ladens ein neuer Auftrag (App kurz zu und wieder auf), wird danach noch einmal geladen –
    /// sonst blieben die Haltestellen verborgen, bis man von Hand neu lädt.
    private var nochmal = false

    init() {
        if let n = Ablage.lesen(Nahbereich.self, "nah") {
            seiten = n.haltestellen.map(HaltModell.init)
            gehzeiten = n.gehzeiten
            ortDerHaltestellen = n.ort
        }
    }

    /// Ortsname, der in allen Haltestellennamen steckt („Potsdam, …“) – wird beim Anzeigen weggelassen.
    var ort: String? { Namen.ort(unter: seiten.map(\.halt.name)) }

    /// Die Haltestellen, die man sehen darf.
    var sichtbar: [HaltModell] { veraltet ? [] : seiten }

    func modell(_ id: String) -> HaltModell? { seiten.first { $0.id == id } }

    /// Beim Schließen der App: alte Haltestellen nicht mehr zeigen.
    func zurueckgelassen() {
        veraltet = true
    }

    /// Standort holen, bei Bedarf Haltestellen neu suchen, dann die Abfahrten aller Haltestellen laden.
    func allesNeu() async {
        guard !beschaeftigt else {
            // Nur nachholen, wenn die App zwischendurch zu war – sonst ist der laufende Durchgang frisch genug
            // (und die Lok käme sonst ein zweites Mal).
            if veraltet { nochmal = true }
            return
        }
        beschaeftigt = true
        laedt = true
        defer {
            laedt = false
            beschaeftigt = false
            if nochmal {
                nochmal = false
                Task { await allesNeu() }
            }
        }
        guard let ort = await standort.frisch() else { return }
        defer { Task { await netzplaene(bei: ort) } }
        // Eine ungefähre Ortung schwankt etwas – erst wer wirklich woanders ist, bekommt neue Haltestellen.
        let spielraum = max(120, min(ort.horizontalAccuracy, 200))
        let weit = ortDerHaltestellen.map { $0.distance(from: ort) > spielraum } ?? true
        if weit && veraltet {
            // Woanders aufgemacht: Die alten Haltestellen verschwinden sofort.
            seiten = []
            jwd = false
        }
        veraltet = false
        var vorab: Task<Void, Never>?
        var vorgeladen: [HaltModell] = []
        if weit || seiten.isEmpty {
            do {
                let alle = try await Fahrplan.kandidaten(bei: ort.coordinate)
                // Die Auswahl nach Luftlinie liegt fast immer richtig: Deren Abfahrten laden schon,
                // während Apple Karten noch die Fußwege rechnet.
                let alt = Dictionary(seiten.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                vorgeladen = Fahrplan.auswaehlen(alle) { Fahrplan.gehzeit(von: ort, zu: $0) }
                    .map { alt[$0.id] ?? HaltModell($0) }
                let schonDa = vorgeladen
                vorab = Task { await Umgebung.laden(schonDa) }
                gehzeiten = await Gehwege.zeiten(von: ort, zu: Gehwege.auswahl(alle, um: ort))
                let liste = Fahrplan.auswaehlen(alle) { gehzeit(zu: $0, von: ort) }
                ortDerHaltestellen = ort
                ohneNetz = false
                jwd = (liste.first?.ort.distance(from: ort) ?? .infinity) > Fahrplan.jwdMeter
                if liste.map(\.id) != seiten.map(\.id) {
                    let bekannt = Dictionary((seiten + vorgeladen).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    seiten = liste.map { bekannt[$0.id] ?? HaltModell($0) }
                }
                Ablage.schreiben(Nahbereich(breite: ort.coordinate.latitude, laenge: ort.coordinate.longitude,
                                            haltestellen: liste, gehzeiten: gehzeiten), "nah")
            } catch {
                ohneNetz = true
            }
        }
        // Die Haltestellen stehen – die Lok darf abfahren. Die Abfahrten laden im Hintergrund weiter,
        // beim Antippen sind sie dann schon da.
        laedt = false
        let rest = seiten.filter { m in !vorgeladen.contains { $0 === m } }
        await Umgebung.laden(rest)
        await vorab?.value
        if let erste = seiten.first { ohneNetz = erste.ohneNetz }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Abfahrten mehrerer Haltestellen gleichzeitig laden.
    private static func laden(_ modelle: [HaltModell]) async {
        await withTaskGroup(of: Void.self) { gruppe in
            for m in modelle { gruppe.addTask { await m.laden() } }
        }
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
