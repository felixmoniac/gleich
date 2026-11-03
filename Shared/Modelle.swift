import Foundation
import CoreLocation

/// Verkehrsmittel – so grob, wie man sie im Alltag unterscheidet.
enum Verkehrsmittel: String, Codable, CaseIterable, Hashable {
    case fern, regio, sbahn, ubahn, tram, bus, faehre, sonst

    /// Reihenfolge der Filter-Symbole oben in der Haltestelle.
    static let reihenfolge: [Verkehrsmittel] = [.fern, .regio, .sbahn, .ubahn, .tram, .bus, .faehre, .sonst]

    var istZug: Bool { self == .fern || self == .regio }
}

struct Linie: Codable, Hashable {
    var name: String
    var mittel: Verkehrsmittel
    /// Linienfarbe aus den Fahrplandaten (z. B. „816da6“), nur für S- und U-Bahn genutzt.
    var farbe: String?
}

enum Quelle: String, Codable, Hashable {
    case transitous, vbb
}

struct Haltestelle: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var breite: Double
    var laenge: Double
    var quelle: Quelle
    /// Was hier fährt – soweit die Datenquelle es verrät.
    var mittel: [Verkehrsmittel] = []
    /// Linien, die hier halten (nur beim VBB bekannt).
    var linien: [String] = []

    var koordinate: CLLocationCoordinate2D { .init(latitude: breite, longitude: laenge) }
    var ort: CLLocation { CLLocation(latitude: breite, longitude: laenge) }
}

struct Abfahrt: Codable, Hashable, Identifiable {
    var id: String
    var linie: Linie
    var richtung: String
    var geplant: Date
    var echt: Date?
    var gleis: String?
    var faelltAus: Bool
    var fahrtID: String
    var quelle: Quelle
    /// Name der Teil-Haltestelle, an der die Abfahrt stattfindet (für die Fahrtansicht).
    var halt: String

    var zeit: Date { echt ?? geplant }
    var verspaetet: Bool { (echt ?? geplant).timeIntervalSince(geplant) >= 60 }
}

struct Zwischenhalt: Hashable, Identifiable {
    var id: Int
    var name: String
    var geplant: Date?
    var echt: Date?
    var faelltAus: Bool = false

    var zeit: Date? { echt ?? geplant }
    var verspaetet: Bool {
        guard let g = geplant, let e = echt else { return false }
        return e.timeIntervalSince(g) >= 60
    }
}

struct Abschnitt: Hashable, Identifiable {
    var id: Int
    /// nil = Fußweg
    var linie: Linie?
    var richtung: String
    var von: String
    var nach: String
    var abGeplant: Date
    var abEcht: Date?
    var anGeplant: Date
    var anEcht: Date?
    var gleis: String?
    var meter: Double?
    var fahrtID: String?
    var zwischenhalte: [Zwischenhalt]

    var ab: Date { abEcht ?? abGeplant }
    var an: Date { anEcht ?? anGeplant }
    var abVerspaetet: Bool { ab.timeIntervalSince(abGeplant) >= 60 }
    var anVerspaetet: Bool { an.timeIntervalSince(anGeplant) >= 60 }
    var istFussweg: Bool { linie == nil }
}

struct Verbindung: Hashable, Identifiable {
    var id: String
    var abschnitte: [Abschnitt]

    var fahrten: [Abschnitt] { abschnitte.filter { !$0.istFussweg } }
    var ab: Date { abschnitte.first?.ab ?? .now }
    var an: Date { abschnitte.last?.an ?? .now }
    var abGeplant: Date { abschnitte.first?.abGeplant ?? .now }
    var anGeplant: Date { abschnitte.last?.anGeplant ?? .now }
}

/// Ein Ziel für die Suche: Haltestelle, Adresse oder Ort.
struct Ziel: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var zusatz: String?
    var breite: Double
    var laenge: Double
    /// Haltestellen-Kennung bei Transitous, falls es eine Haltestelle ist.
    var haltID: String?

    /// So versteht Transitous das Ziel.
    var anfrage: String { haltID ?? "\(breite),\(laenge)" }
}
