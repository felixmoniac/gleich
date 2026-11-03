import SwiftUI
import Observation

/// Rauchringe der kleinen Lok: Sie wachsen, verlassen den Kreis und ziehen über den Bildschirm.
/// Wer einen antippt, bekommt einen Zen-Spruch. Ringe und Sprüche verblassen von selbst.
@Observable
final class Rauch {
    struct Ring: Identifiable {
        let id = UUID()
        let start: CGPoint
        let richtung: CGVector
        let tempo: CGFloat
        let wackel: Double
        let geburt = Date.now
    }

    struct Spruch: Identifiable {
        let id = UUID()
        let text: String
        let ort: CGPoint
        let geburt = Date.now
    }

    static let ringDauer = 9.0
    static let spruchDauer = 6.0

    private(set) var ringe: [Ring] = []
    private(set) var sprueche: [Spruch] = []

    var istLeer: Bool { ringe.isEmpty && sprueche.isEmpty }

    /// Neuer Ring am Schornstein, fliegt grob von der Kreismitte weg.
    func ausstossen(bei ort: CGPoint, weg mitte: CGPoint) {
        var dx = ort.x - mitte.x, dy = ort.y - mitte.y
        let laenge = max(1, (dx * dx + dy * dy).squareRoot())
        dx /= laenge; dy /= laenge
        // Etwas streuen, und leicht nach oben treiben lassen, wie Rauch eben
        let streu = Double.random(in: -0.6...0.6)
        let rx = dx * CGFloat(cos(streu)) - dy * CGFloat(sin(streu))
        let ry = dx * CGFloat(sin(streu)) + dy * CGFloat(cos(streu)) - 0.35
        ringe.append(Ring(start: ort, richtung: CGVector(dx: rx, dy: ry),
                          tempo: .random(in: 34...62), wackel: .random(in: 0...(2 * .pi))))
    }

    /// Ring verschwindet, an seiner Stelle erscheint ein Spruch.
    func antippen(_ ring: Ring, ort: CGPoint) {
        ringe.removeAll { $0.id == ring.id }
        sprueche.append(Spruch(text: Zen.naechster(), ort: ort))
    }

    func aufraeumen() {
        let jetzt = Date.now
        ringe.removeAll { jetzt.timeIntervalSince($0.geburt) > Rauch.ringDauer }
        sprueche.removeAll { jetzt.timeIntervalSince($0.geburt) > Rauch.spruchDauer }
    }

    func leeren() {
        ringe = []
        sprueche = []
    }

    /// Wo ein Ring gerade ist, wie groß und wie sichtbar.
    static func zustand(_ ring: Ring, jetzt: Date) -> (ort: CGPoint, radius: CGFloat, deckkraft: Double) {
        let a = jetzt.timeIntervalSince(ring.geburt)
        let f = min(1, a / ringDauer)
        // Erst flott, dann gemächlich
        let weg = ring.tempo * CGFloat(a) * CGFloat(1 - f * 0.45)
        let quer = CGFloat(sin(a * 1.3 + ring.wackel)) * 10
        let ort = CGPoint(x: ring.start.x + ring.richtung.dx * weg - ring.richtung.dy * quer,
                          y: ring.start.y + ring.richtung.dy * weg + ring.richtung.dx * quer)
        let radius = 4 + 46 * CGFloat(pow(f, 0.6))
        let ein = min(1, a / 0.4)
        let aus = a > ringDauer - 2 ? max(0, (ringDauer - a) / 2) : 1
        return (ort, radius, ein * aus)
    }
}

/// Liegt über der ganzen Suche: zeigt Ringe und Sprüche. Leere Stellen lassen Berührungen durch.
struct RauchBild: View {
    var rauch: Rauch

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: rauch.istLeer)) { zeit in
                ZStack {
                    ForEach(rauch.ringe) { ring in
                        let z = Rauch.zustand(ring, jetzt: zeit.date)
                        Circle()
                            .stroke(Color.primary.opacity(0.55 * z.deckkraft), lineWidth: 1.8)
                            .frame(width: z.radius * 2, height: z.radius * 2)
                            .contentShape(Circle())
                            .position(z.ort)
                            .onTapGesture { rauch.antippen(ring, ort: z.ort) }
                    }
                    ForEach(rauch.sprueche) { s in
                        SpruchBild(spruch: s, jetzt: zeit.date, flaeche: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                rauch.aufraeumen()
            }
        }
    }
}

struct SpruchBild: View {
    var spruch: Rauch.Spruch
    var jetzt: Date
    var flaeche: CGSize

    var body: some View {
        let a = jetzt.timeIntervalSince(spruch.geburt)
        let ein = min(1, a / 0.6)
        let aus = a > Rauch.spruchDauer - 1.6 ? max(0, (Rauch.spruchDauer - a) / 1.6) : 1
        let breite: CGFloat = 260
        // Im Bild halten, auch wenn der Ring am Rand war
        let x = min(max(spruch.ort.x, breite / 2 + 16), flaeche.width - breite / 2 - 16)
        let y = min(max(spruch.ort.y, 60), flaeche.height - 140)
        Text(spruch.text)
            .font(.system(.title3, design: .serif).italic())
            .multilineTextAlignment(.center)
            .frame(width: breite)
            .padding(.vertical, 10)
            .background(Color(.systemBackground).opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(0.9 + 0.1 * ein)
            .blur(radius: (1 - aus) * 6)
            .opacity(ein * aus)
            .position(x: x, y: y)
            .allowsHitTesting(false)
    }
}
