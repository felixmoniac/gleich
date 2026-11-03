import Foundation

/// Macht Haltestellennamen kurz und lesbar: „S+U Alexanderplatz Bhf (Berlin)“ → „Alexanderplatz“.
enum Namen {
    static func kurz(_ name: String, ort: String? = nil) -> String {
        var s = name.trimmingCharacters(in: .whitespaces)
        for klammer in [" (Berlin)", " (Bln)", " (Potsdam)"] {
            s = s.replacingOccurrences(of: klammer, with: "")
        }
        for vorne in ["S+U ", "S+U-", "U+S ", "S ", "U "] where s.hasPrefix(vorne) {
            s.removeFirst(vorne.count)
            break
        }
        for (alt, neu) in [(", Hauptbahnhof", " Hbf"), (", Hbf", " Hbf"), (", Bahnhof", ""), (", Bhf", "")] where s.hasSuffix(alt) {
            s = String(s.dropLast(alt.count)) + neu
        }
        for hinten in [" Bhf", " Bahnhof"] where s.hasSuffix(hinten) && s.count > hinten.count + 3 {
            s.removeLast(hinten.count)
        }
        if let ort, !ort.isEmpty {
            for trenner in [", ", " "] where s.hasPrefix(ort + trenner) && s.count > ort.count + 4
                && !["Hbf", "Hauptbahnhof"].contains(String(s.dropFirst(ort.count + trenner.count))) {
                s.removeFirst(ort.count + trenner.count)
                break
            }
        }
        return s
    }

    /// Ort aus „Potsdam, Lange Brücke“ → „Potsdam“.
    static func ort(aus name: String) -> String? {
        guard let komma = name.firstIndex(of: ",") else { return nil }
        let o = name[..<komma].trimmingCharacters(in: .whitespaces)
        return o.isEmpty ? nil : String(o)
    }

    /// Häufigster Ort unter den Haltestellen in der Nähe.
    static func ort(unter namen: [String]) -> String? {
        let orte = namen.compactMap { ort(aus: $0) }
        let zaehlung = Dictionary(orte.map { ($0, 1) }, uniquingKeysWith: +)
        return zaehlung.max { $0.value < $1.value }?.key
    }

    /// Vergleichsform, um Teile desselben Bahnhofs zu erkennen.
    static func kern(_ name: String) -> String {
        kurz(name).lowercased()
            .replacingOccurrences(of: "hauptbahnhof", with: "hbf")
            .filter { $0.isLetter || $0.isNumber }
    }
}
