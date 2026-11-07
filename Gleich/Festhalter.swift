import ActivityKit
import BackgroundTasks
import Foundation
import Observation

/// Die festgehaltene Verbindung samt Ziel – übersteht das Schließen der App.
struct Festgehalten: Codable, Equatable {
    var ziel: Ziel
    var verbindung: Verbindung
}

/// Hält eine Verbindung fest: auf der Startseite, auf dem Sperrbildschirm, mit aufgefrischten Zeiten.
/// Es gibt immer nur eine – wer eine neue festhält, lässt die alte los.
@Observable
final class Festhalter {
    static let geteilt = Festhalter()
    /// Kennung für das Auffrischen im Hintergrund (muss in Gleich-Info.plist stehen).
    static let auftrag = "com.fmoniac.Gleich.fest"

    private(set) var fest: Festgehalten?
    private(set) var laedt = false

    private init() {
        fest = Ablage.lesen(Festgehalten.self, "fest")
        if istVorbei { loslassen() }
    }

    func istFest(_ v: Verbindung) -> Bool { fest?.verbindung.kennung == v.kennung }

    /// Zehn Minuten nach der Ankunft ist die Fahrt erledigt.
    private var istVorbei: Bool {
        guard let f = fest else { return false }
        return f.verbindung.an < .now.addingTimeInterval(-10 * 60)
    }

    func festhalten(_ v: Verbindung, ziel: Ziel) {
        fest = Festgehalten(ziel: ziel, verbindung: v)
        sichern()
        Task { await aktivitaetStarten() }
        planen()
    }

    func loslassen() {
        fest = nil
        Ablage.standard.removeObject(forKey: "fest")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Festhalter.auftrag)
        Task { await aktivitaetenBeenden() }
    }

    /// Holt für jede Fahrt der Verbindung die aktuellen Zeiten – keine neue Suche, genau diese Züge und Busse.
    func auffrischen() async {
        if istVorbei { loslassen() }
        guard let alt = fest, !laedt else { return }
        laedt = true
        defer { laedt = false }
        var abschnitte = alt.verbindung.abschnitte
        await withTaskGroup(of: (Int, [Transitous.HaltZeit]?).self) { gruppe in
            for (i, a) in abschnitte.enumerated() where !a.istFussweg {
                guard let fahrt = a.fahrtID, !fahrt.isEmpty else { continue }
                gruppe.addTask { (i, try? await Transitous.halte(fahrt: fahrt)) }
            }
            for await (i, halte) in gruppe {
                if let halte, !halte.isEmpty { abschnitte[i].auffrischen(mit: halte) }
            }
        }
        // Inzwischen losgelassen oder eine andere festgehalten? Dann nichts überschreiben.
        guard var f = fest, f.verbindung.kennung == alt.verbindung.kennung else { return }
        f.verbindung.abschnitte = abschnitte
        fest = f
        sichern()
        await aktivitaetAktualisieren()
    }

    /// Bittet iOS, die App in ein paar Minuten kurz im Hintergrund zu wecken. Ob und wann, entscheidet iOS.
    func planen() {
        guard fest != nil else { return }
        let anfrage = BGAppRefreshTaskRequest(identifier: Festhalter.auftrag)
        anfrage.earliestBeginDate = .now.addingTimeInterval(5 * 60)
        try? BGTaskScheduler.shared.submit(anfrage)
    }

    private func sichern() {
        if let fest { Ablage.schreiben(fest, "fest") }
    }

    // MARK: Sperrbildschirm

    private func inhalt(_ f: Festgehalten) -> ActivityContent<FahrtAktivitaet.ContentState> {
        // Kurz nach der Ankunft gilt die Anzeige als überholt und wird blass.
        ActivityContent(state: FahrtAktivitaet.ContentState(f.verbindung),
                        staleDate: f.verbindung.an.addingTimeInterval(2 * 60))
    }

    private func aktivitaetStarten() async {
        await aktivitaetenBeenden()
        guard let f = fest, !f.verbindung.fahrten.isEmpty,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(attributes: FahrtAktivitaet(ziel: Namen.kurz(f.ziel.name)),
                                  content: inhalt(f), pushType: nil)
    }

    private func aktivitaetAktualisieren() async {
        guard let f = fest else { return }
        let laufende = Activity<FahrtAktivitaet>.activities
        // Ist sie verschwunden (etwa nach einem Neustart des iPhones), kommt sie wieder – das geht nur bei offener App.
        if laufende.isEmpty {
            await aktivitaetStarten()
            return
        }
        for a in laufende { await a.update(inhalt(f)) }
    }

    private func aktivitaetenBeenden() async {
        for a in Activity<FahrtAktivitaet>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }
}

private extension Abschnitt {
    /// Trägt die aktuellen Zeiten ein: Einstieg und Ausstieg werden über die geplante Zeit gefunden,
    /// bei Gleichstand hilft der Name.
    mutating func auffrischen(mit halte: [Transitous.HaltZeit]) {
        func passt(_ a: Date?, _ b: Date?) -> Bool {
            guard let a, let b else { return false }
            return abs(a.timeIntervalSince(b)) < 45
        }
        func gleich(_ name: String, _ h: Transitous.HaltZeit) -> Bool {
            let a = Namen.kern(name), b = Namen.kern(h.name)
            return a.hasPrefix(b) || b.hasPrefix(a)
        }
        let ein = halte.first { passt($0.abGeplant, abGeplant) && gleich(von, $0) }
            ?? halte.first { passt($0.abGeplant, abGeplant) }
        let aus = halte.last { passt($0.anGeplant, anGeplant) && gleich(nach, $0) }
            ?? halte.last { passt($0.anGeplant, anGeplant) }
        if let ein {
            abEcht = ein.ab
            if let g = ein.gleis, linie?.mittel.istZug == true || linie?.mittel == .sbahn { gleis = g }
        }
        if let aus { anEcht = aus.an }
        faelltAus = (ein?.faelltAus ?? false) || (aus?.faelltAus ?? false)
        for i in zwischenhalte.indices {
            if let h = halte.first(where: { passt($0.abGeplant ?? $0.anGeplant, zwischenhalte[i].geplant) }) {
                zwischenhalte[i].echt = h.ab ?? h.an
                zwischenhalte[i].faelltAus = h.faelltAus
            }
        }
    }
}
