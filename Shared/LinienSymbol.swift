import SwiftUI

/// Liniensymbol in den vertrauten Farben: S-Bahn rund, U-Bahn eckig, Tram rot, Bus lila.
struct LinienSymbol: View {
    var linie: Linie
    var klein = false

    var body: some View {
        Text(linie.name)
            .font(.system(size: klein ? 12 : 15, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, klein ? 5 : 7)
            .frame(minWidth: klein ? 30 : 54, minHeight: klein ? 18 : 24)
            .background(LinienSymbol.farbe(linie), in: form)
    }

    private var form: some Shape {
        switch linie.mittel {
        case .sbahn: AnyShape(Capsule())
        case .ubahn: AnyShape(RoundedRectangle(cornerRadius: 3))
        default: AnyShape(RoundedRectangle(cornerRadius: klein ? 4 : 6))
        }
    }

    static func farbe(_ l: Linie) -> Color {
        switch l.mittel {
        case .sbahn: return Color(hex: l.farbe, sonst: 0x008D4F)
        case .ubahn: return Color(hex: l.farbe, sonst: 0x115D91)
        case .tram: return Color(hex: 0xC8102E)
        case .bus: return Color(hex: 0x8E2C79)
        case .regio: return Color(hex: 0xE2001A)
        case .fern: return Color(hex: 0x3D4147)
        case .faehre: return Color(hex: 0x0098D8)
        case .sonst: return Color(hex: 0x6E6E73)
        }
    }
}

/// Kleines Symbol für ein Verkehrsmittel (Filterreihe oben).
struct MittelSymbol: View {
    var mittel: Verkehrsmittel

    var body: some View {
        Group {
            switch mittel {
            case .sbahn: buchstabe("S", Capsule())
            case .ubahn: buchstabe("U", RoundedRectangle(cornerRadius: 3))
            case .fern: buchstabe("ICE", RoundedRectangle(cornerRadius: 5))
            case .regio: buchstabe("RE", RoundedRectangle(cornerRadius: 5))
            case .tram: bild("tram.fill")
            case .bus: bild("bus.fill")
            case .faehre: bild("ferry.fill")
            case .sonst: bild("circle.grid.2x2.fill")
            }
        }
    }

    private var farbe: Color { LinienSymbol.farbe(Linie(name: "", mittel: mittel)) }

    private func buchstabe(_ s: String, _ form: some Shape) -> some View {
        Text(s)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 30, minHeight: 26)
            .background(farbe, in: form)
    }

    private func bild(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 26)
            .background(farbe, in: RoundedRectangle(cornerRadius: 6))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Farbe aus Text wie „816da6“; zu helle oder fehlende Farben werden ersetzt.
    init(hex text: String?, sonst: UInt32) {
        guard let text, text.count == 6, let wert = UInt32(text, radix: 16) else {
            self.init(hex: sonst); return
        }
        let r = Double((wert >> 16) & 0xFF), g = Double((wert >> 8) & 0xFF), b = Double(wert & 0xFF)
        let hell = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        let unbunt = max(r, g, b) - min(r, g, b) < 20
        self.init(hex: (hell > 0.8 || unbunt) ? sonst : wert)
    }
}
