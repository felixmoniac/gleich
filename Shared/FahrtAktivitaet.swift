import ActivityKit
import Foundation

/// Eine festgehaltene Verbindung auf dem Sperrbildschirm und in der Dynamic Island.
/// App und Widget teilen sich diese Beschreibung.
struct FahrtAktivitaet: ActivityAttributes {
    /// Wohin es geht.
    var ziel: String

    struct ContentState: Codable, Hashable {
        /// Nur die Fahrten, ohne Fußwege.
        var teile: [Teil]
        /// Welche Fahrt als nächste dran ist (Stelle in `teile`).
        var naechste: Int
        var an: Date
        var anGeplant: Date
    }

    struct Teil: Codable, Hashable {
        var linie: Linie
        var von: String
        var nach: String
        var ab: Date
        var abGeplant: Date
        var an: Date
        var gleis: String?
        var faelltAus: Bool

        var abVerspaetet: Bool { ab.timeIntervalSince(abGeplant) >= 60 }
    }
}

extension FahrtAktivitaet.ContentState {
    init(_ v: Verbindung, jetzt: Date = .now) {
        let teile = v.fahrten.map { a in
            FahrtAktivitaet.Teil(linie: a.linie ?? Linie(name: "?", mittel: .sonst), von: Namen.kurz(a.von),
                                 nach: Namen.kurz(a.nach), ab: a.ab, abGeplant: a.abGeplant, an: a.an,
                                 gleis: a.gleis, faelltAus: a.faelltAus)
        }
        self.teile = teile
        // Wer schon im Zug sitzt, will den nächsten Umstieg sehen.
        naechste = teile.firstIndex { $0.ab > jetzt.addingTimeInterval(-30) } ?? max(teile.count - 1, 0)
        an = v.an
        anGeplant = v.anGeplant
    }

    var anVerspaetet: Bool { an.timeIntervalSince(anGeplant) >= 60 }
}
