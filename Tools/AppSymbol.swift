// Zeichnet das App-Symbol: die Strich-Lok aus der App, hell auf Dunkelgrün.
// Aufruf: Tools/appsymbol.sh
import SwiftUI
import AppKit

@MainActor
func zeichnen(_ ziel: String) {
    let bild = ZStack {
        LinearGradient(colors: [Color(red: 0.07, green: 0.42, blue: 0.31), Color(red: 0.03, green: 0.27, blue: 0.20)],
                       startPoint: .top, endPoint: .bottom)
        Lok(ruckelt: false, strecke: 9)
            .foregroundStyle(Color(red: 1, green: 0.96, blue: 0.86))
            .scaleEffect(11)
            .offset(x: 6, y: -48)
        Dampf()
            .stroke(Color(red: 1, green: 0.96, blue: 0.86).opacity(0.9), lineWidth: 15)
            .frame(width: 1024, height: 1024)
    }
    .frame(width: 1024, height: 1024)
    let r = ImageRenderer(content: bild)
    r.scale = 1
    guard let cg = r.cgImage else { fatalError("kein Bild") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ziel))
}

/// Zwei Dampfwolken über dem Schornstein.
struct Dampf: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (x, y, g) in [(690.0, 300.0, 44.0), (570.0, 195.0, 62.0)] {
            p.addEllipse(in: CGRect(x: x - g, y: y - g * 0.8, width: g * 2, height: g * 1.6))
            p.addEllipse(in: CGRect(x: x - g * 1.6, y: y - g * 0.3, width: g * 1.3, height: g * 1.1))
            p.addEllipse(in: CGRect(x: x + g * 0.4, y: y - g * 0.2, width: g * 1.2, height: g))
        }
        return p
    }
}

@main struct Haupt { static func main() { MainActor.assumeIsolated { zeichnen(CommandLine.arguments[1]) } } }
