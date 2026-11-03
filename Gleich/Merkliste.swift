import Foundation
import Observation

struct Gemerkt: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var ziel: Ziel

    var symbol: String {
        switch name.lowercased() {
        case "zuhause", "daheim", "zu hause", "home": "house.fill"
        case "arbeit", "büro", "buero", "job": "briefcase.fill"
        case "schule", "kita": "graduationcap.fill"
        default: "star.fill"
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
