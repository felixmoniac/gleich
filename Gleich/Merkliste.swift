import Foundation
import Observation

struct Gemerkt: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var ziel: Ziel

    var symbol: String { Gemerkt.symbol(fuer: name) }

    static func symbol(fuer name: String) -> String {
        switch art(name) {
        case "zuhause": "house.fill"
        case "arbeit": "briefcase.fill"
        case "schule": "graduationcap.fill"
        default: "star.fill"
        }
    }

    /// Fasst gleichbedeutende Namen zusammen: „Daheim“ ist auch Zuhause.
    static func art(_ name: String) -> String {
        switch name.lowercased().trimmingCharacters(in: .whitespaces) {
        case "zuhause", "daheim", "zu hause", "home": "zuhause"
        case "arbeit", "büro", "buero", "job": "arbeit"
        case "schule", "kita": "schule"
        case let n: n
        }
    }
}

@Observable
final class Merkliste {
    private(set) var orte: [Gemerkt]

    init() {
        orte = Ablage.lesen([Gemerkt].self, "gemerkt") ?? []
    }

    func merken(_ ziel: Ziel, als name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        orte.append(Gemerkt(name: n.isEmpty ? ziel.name : n, ziel: ziel))
        sichern()
    }

    /// Der gemerkte Ort für Zuhause, Arbeit usw., falls es ihn gibt.
    func ort(_ name: String) -> Gemerkt? {
        orte.first { Gemerkt.art($0.name) == Gemerkt.art(name) }
    }

    /// Wie merken, ersetzt aber einen Ort gleichen Namens (etwa ein neues Zuhause).
    func festlegen(_ ziel: Ziel, als name: String) {
        if let i = orte.firstIndex(where: { Gemerkt.art($0.name) == Gemerkt.art(name) }) {
            orte[i].ziel = ziel
            sichern()
        } else {
            merken(ziel, als: name)
        }
    }

    func umbenennen(_ g: Gemerkt, in name: String) {
        guard let i = orte.firstIndex(of: g) else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { orte[i].name = n }
        sichern()
    }

    func vergessen(_ g: Gemerkt) {
        orte.removeAll { $0.id == g.id }
        sichern()
    }

    func istGemerkt(_ ziel: Ziel) -> Bool { orte.contains { $0.ziel.id == ziel.id } }

    private func sichern() { Ablage.schreiben(orte, "gemerkt") }
}
