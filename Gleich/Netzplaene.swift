import Foundation
import CoreLocation
import Observation

struct Netzplan: Codable, Hashable, Identifiable {
    var titel: String
    var adresse: URL
    var id: String { adresse.absoluteString }

    /// Wo die heruntergeladene Datei liegt.
    var datei: URL {
        let name = adresse.absoluteString.data(using: .utf8)!.base64EncodedString()
            .filter { $0.isLetter || $0.isNumber }.suffix(60)
        return Planablage.ordner.appendingPathComponent(String(name) + ".pdf")
    }
}

/// Ein Verkehrsverbund und wo seine Netzpläne zu finden sind.
/// Es gibt keine gemeinsame Quelle für ganz Deutschland – jeder Verbund stellt seine Pläne selbst ins Netz.
/// Wo möglich, liest die App die Übersichtsseite des Verbunds, damit neue Ausgaben von selbst gefunden werden.
struct Verbund {
    var name: String
    var kuerzel: String
    /// Grobes Gebiet als Rechteck: Breite von–bis, Länge von–bis.
    var gebiet: (ClosedRange<Double>, ClosedRange<Double>)
    /// Übersichtsseiten mit PDF-Links.
    var seiten: [String] = []
    /// Wichtige Pläne: Titel und ein Stück der Dateiadresse, an dem sie zu erkennen sind.
    var feste: [(String, String)] = []
    /// Pläne mit fester Adresse.
    var direkt: [(String, String)] = []

    func enthaelt(_ o: CLLocationCoordinate2D) -> Bool {
        gebiet.0.contains(o.latitude) && gebiet.1.contains(o.longitude)
    }

    /// Reihenfolge zählt: Die kleineren Gebiete zuerst, Berlin-Brandenburg zuletzt.
    static let alle: [Verbund] = [
        Verbund(name: "Verkehrsverbund Oberelbe", kuerzel: "VVO", gebiet: (50.75...51.45, 13.2...14.5),
                seiten: ["https://www.vvo-online.de/de/linien-plaene/liniennetz/index.cshtml",
                         "https://www.vvo-online.de/de/linien-plaene/stadtverkehr/index.cshtml"],
                feste: [("Liniennetz VVO", "VVO-Liniennetzplan-topografisch"),
                        ("Dresden", "Liniennetzplan-Stadt-Dresden.pdf")]),
        Verbund(name: "Hamburger Verkehrsverbund", kuerzel: "HVV", gebiet: (53.2...54.0, 9.2...10.8),
                direkt: [("Schnellbahn und Regionalverkehr",
                          "https://www.hvv.de/resource/blob/120104/3ff58f395fa6e8d4818231b0573b0bc6/hvv_usar-plan.pdf")]),
        Verbund(name: "Münchner Verkehrs- und Tarifverbund", kuerzel: "MVV", gebiet: (47.6...48.7, 11.0...12.6),
                seiten: ["https://www.mvv-muenchen.de/netz-plaene-medien/plaene/netzplaene/download/gesamtnetz/"],
                feste: [("S-Bahn, U-Bahn, Regionalzug", "SUR_M_12"),
                        ("Innenraum mit Tram", "SURTX_M"),
                        ("Tram", "Tramnetz"),
                        ("Nachtnetz", "Nachtnetz"),
                        ("Regionalbusse", "Regio_0GESAMT")]),
        Verbund(name: "Rhein-Main-Verkehrsverbund", kuerzel: "RMV", gebiet: (49.6...50.9, 7.8...10.2),
                seiten: ["https://www.vgf-ffm.de/en/tickets-fares-plans/route-plans"],
                feste: [("Schnellbahnplan", "Schnellbahnplan_Grossraum"),
                        ("Regionalzüge", "RegionalerSchienennetzplan"),
                        ("Frankfurt", "Liniennetzplan_Frankfurt_2"),
                        ("Frankfurt Nachtnetz", "Nachtnetzplan_Frankfurt")]),
        Verbund(name: "Verkehrsverbund Rhein-Ruhr", kuerzel: "VRR", gebiet: (51.05...51.75, 6.2...7.6),
                seiten: ["https://www.vrr.de/de/fahrplan-mobilitaet/stadt-linien-netzplaene/"],
                feste: [("Schnellverkehrsplan", "Schienenschnellverkehrsplan")]),
        Verbund(name: "Verkehrsverbund Rhein-Sieg", kuerzel: "VRS", gebiet: (50.55...51.05, 6.5...7.75),
                seiten: ["https://www.vrs.de/en/verbindungen/liniennetz/rail-and-bus-network-plans"],
                feste: [("S-Bahn", "SBahnNetz"),
                        ("Regionalverkehr NRW", "NRW_Regionalverkehrsplan")]),
        Verbund(name: "Verkehrs- und Tarifverbund Stuttgart", kuerzel: "VVS", gebiet: (48.55...49.05, 8.8...9.75),
                direkt: [("S-Bahn und Stadtbahn",
                          "https://www.vvs.de/fileadmin/2_Verbindungen_und_Mobilitaet/2.3_Liniennetz_und_Tarifzonenplan/S-Bahn_Stadtbahn/Verbund_Schienennetz.pdf")]),
        Verbund(name: "Verkehrsverbund Berlin-Brandenburg", kuerzel: "VBB", gebiet: (51.35...53.56, 11.26...14.77),
                seiten: ["https://www.vbb.de/unterwegs-im-vbb/liniennetze/"],
                feste: [("S- und U-Bahn Berlin", "berlin-s-u-schnellbahn"),
                        ("Regionalverkehr", "bahn-regionalverkehr-brandenburg-und-berlin.pdf")]),
    ]

    static func an(_ o: CLLocationCoordinate2D) -> Verbund? { alle.first { $0.enthaelt(o) } }
}

/// Lädt die Netzpläne des Verbunds, in dem man gerade ist, und hält sie ohne Netz bereit.
@Observable
final class Planablage {
    static let ordner: URL = {
        let o = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Netzplaene", isDirectory: true)
        try? FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
        return o
    }()

    var verbund: Verbund?
    var plaene: [Netzplan] = []
    /// Fertig heruntergeladene Pläne.
    var bereit: Set<String> = []
    private var stand: (String, [String], Date)?

    init() {
        plaene = Ablage.lesen([Netzplan].self, "netzplaene") ?? []
        bereit = Set(plaene.filter { FileManager.default.fileExists(atPath: $0.datei.path) }.map(\.id))
    }

    func aktualisieren(bei o: CLLocationCoordinate2D, orte: [String]) async {
        let v = Verbund.an(o)
        verbund = v
        guard let v else { return }
        // Höchstens alle sechs Stunden neu nachsehen, außer Verbund oder Ort haben gewechselt.
        if let s = stand, s.0 == v.kuerzel, s.1 == orte, Date.now.timeIntervalSince(s.2) < 6 * 3600 { return }
        let liste = await Planablage.suchen(v, orte: orte)
        guard !liste.isEmpty else { return }
        stand = (v.kuerzel, orte, .now)
        plaene = liste
        Ablage.schreiben(liste, "netzplaene")
        bereit = Set(liste.filter { FileManager.default.fileExists(atPath: $0.datei.path) }.map(\.id))
        for p in liste where !bereit.contains(p.id) {
            if await Planablage.herunterladen(p) { bereit.insert(p.id) }
        }
    }

    private static func herunterladen(_ p: Netzplan) async -> Bool {
        var anfrage = URLRequest(url: p.adresse)
        anfrage.setValue(Netz.kennung, forHTTPHeaderField: "User-Agent")
        guard let (tmp, antwort) = try? await URLSession.shared.download(for: anfrage),
              (antwort as? HTTPURLResponse)?.statusCode == 200 else { return false }
        try? FileManager.default.removeItem(at: p.datei)
        return (try? FileManager.default.moveItem(at: tmp, to: p.datei)) != nil
    }

    /// Liest die Übersichtsseiten und wählt die wichtigen Pläne und die des aktuellen Orts aus.
    static func suchen(_ v: Verbund, orte: [String]) async -> [Netzplan] {
        var gefunden: [(titel: String, url: URL)] = []
        for seite in v.seiten {
            guard let basis = URL(string: seite) else { continue }
            var anfrage = URLRequest(url: basis)
            anfrage.setValue("Mozilla/5.0 (iPhone) " + Netz.kennung, forHTTPHeaderField: "User-Agent")
            guard let (daten, _) = try? await Netz.sitzung.data(for: anfrage),
                  let html = String(data: daten, encoding: .utf8) ?? String(data: daten, encoding: .isoLatin1) else { continue }
            gefunden += links(in: html, basis: basis)
        }

        var ergebnis: [Netzplan] = []
        func dazu(_ titel: String, _ url: URL) {
            if !ergebnis.contains(where: { $0.adresse == url }) { ergebnis.append(Netzplan(titel: titel, adresse: url)) }
        }
        for (titel, adresse) in v.direkt { if let u = URL(string: adresse) { dazu(titel, u) } }
        for (titel, muster) in v.feste {
            if let treffer = gefunden.first(where: { $0.url.absoluteString.localizedCaseInsensitiveContains(muster) }) {
                dazu(titel, treffer.url)
            }
        }
        // Pläne für den Ort, an dem man gerade ist (z. B. „Potsdam, Tageslinien“).
        let gesucht = orte.map(vergleich).filter { $0.count >= 4 }
        for g in gefunden {
            let text = vergleich(g.titel + " " + g.url.lastPathComponent)
            if gesucht.contains(where: { text.contains($0) }) { dazu(g.titel, g.url) }
        }
        return Array(ergebnis.prefix(8))
    }

    private static func links(in html: String, basis: URL) -> [(titel: String, url: URL)] {
        let muster = try! NSRegularExpression(pattern: #"<a[^>]+href="([^"]+\.pdf[^"]*)"[^>]*>(.*?)</a>"#,
                                              options: [.caseInsensitive, .dotMatchesLineSeparators])
        let ns = html as NSString
        let roh: [(titel: String, url: URL)] = muster.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let href = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: href, relativeTo: basis)?.absoluteURL else { return nil }
            var text = ns.substring(with: m.range(at: 2))
                .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            // „Potsdam, Tageslinien: gültig ab …“ → „Potsdam, Tageslinien“
            if let doppelpunkt = text.range(of: ": gültig") { text = String(text[..<doppelpunkt.lowerBound]) }
            return (text, url)
        }
        // Oft gibt es zu einem Plan zwei Links: ein Bild ohne Text und den Titel. Der Titel gewinnt.
        var titel: [URL: String] = [:]
        for r in roh where !r.titel.isEmpty && titel[r.url] == nil { titel[r.url] = r.titel }
        var gesehen = Set<URL>()
        return roh.compactMap { r in
            guard gesehen.insert(r.url).inserted else { return nil }
            let t = titel[r.url] ?? r.url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            return (t, r.url)
        }
    }

    private static func vergleich(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
            .filter { $0.isLetter }
    }
}
