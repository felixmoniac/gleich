import SwiftUI
import Observation

/// Rauchwolken der kleinen Lok: Sie wachsen, verlassen den Kreis und ziehen über den Bildschirm.
/// Nur eine Wolke trägt einen Zen-Spruch. Wer sie antippt, bekommt ihn – und alle anderen zerplatzen.
/// Andere Wolken zerplatzen beim Antippen einfach. Wolken und Sprüche verblassen von selbst.
@Observable
final class Rauch {
    /// Zufällige Gestalt einer Wolke: Beulen, Dellen, Streckung.
    struct Form {
        let buckel = Int.random(in: 5...9)
        let verzug = Double.random(in: 0.15...0.5)
        let dreh = Double.random(in: 0..<(2 * .pi))
        let a2 = Double.random(in: 0.05...0.14)
        let a3 = Double.random(in: 0.03...0.10)
        let p1 = Double.random(in: 0..<(2 * .pi))
        let p2 = Double.random(in: 0..<(2 * .pi))
        let p3 = Double.random(in: 0..<(2 * .pi))
        let streck = Double.random(in: 0.8...1.25)
    }

    struct Ring: Identifiable {
        let id = UUID()
        let start: CGPoint
        let richtung: CGVector
        let tempo: CGFloat
        let wackel: Double
        let form = Form()
        let traegtSpruch: Bool
        let geburt = Date.now
    }

    /// Eine Wolke, die gerade zerplatzt.
    struct Platzer: Identifiable {
        let id = UUID()
        let ort: CGPoint
        let radius: CGFloat
        let form: Form
        let fetzen: [Double] = (0..<7).map { _ in .random(in: 0..<(2 * .pi)) }
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
    static let platzDauer = 0.45

    private(set) var ringe: [Ring] = []
    private(set) var platzer: [Platzer] = []
    private(set) var sprueche: [Spruch] = []
    /// Während gesucht wird, kommt kein neuer Rauch.
    var ruht = false
    /// So viele Wolken noch, bis wieder eine den Spruch trägt.
    private var bisSpruch = Int.random(in: 1...3)

    var istLeer: Bool { ringe.isEmpty && sprueche.isEmpty && platzer.isEmpty }

    /// Neue Wolke am Schornstein, fliegt grob von der Kreismitte weg.
    func ausstossen(bei ort: CGPoint, weg mitte: CGPoint) {
        guard !ruht else { return }
        var dx = ort.x - mitte.x, dy = ort.y - mitte.y
        let laenge = max(1, (dx * dx + dy * dy).squareRoot())
        dx /= laenge; dy /= laenge
        // Etwas streuen, und leicht nach oben treiben lassen, wie Rauch eben
        let streu = Double.random(in: -0.6...0.6)
        let rx = dx * CGFloat(cos(streu)) - dy * CGFloat(sin(streu))
        let ry = dx * CGFloat(sin(streu)) + dy * CGFloat(cos(streu)) - 0.35
        // Immer nur eine Wolke mit Spruch unterwegs
        var traegt = false
        if sprueche.isEmpty, !ringe.contains(where: \.traegtSpruch) {
            if bisSpruch <= 0 {
                traegt = true
                bisSpruch = .random(in: 2...5)
            } else {
                bisSpruch -= 1
            }
        }
        ringe.append(Ring(start: ort, richtung: CGVector(dx: rx, dy: ry),
                          tempo: .random(in: 34...62), wackel: .random(in: 0...(2 * .pi)), traegtSpruch: traegt))
    }

    /// Die Spruch-Wolke gibt ihren Spruch frei und alle zerplatzen; jede andere zerplatzt allein.
    func antippen(_ ring: Ring) {
        let jetzt = Date.now
        let betroffen = ring.traegtSpruch ? ringe : ringe.filter { $0.id == ring.id }
        for r in betroffen {
            let z = Rauch.zustand(r, jetzt: jetzt)
            platzer.append(Platzer(ort: z.ort, radius: z.radius, form: r.form))
        }
        let weg = Set(betroffen.map(\.id))
        ringe.removeAll { weg.contains($0.id) }
        if ring.traegtSpruch {
            sprueche.append(Spruch(text: Zen.naechster(), ort: Rauch.zustand(ring, jetzt: jetzt).ort))
        }
    }

    func aufraeumen() {
        let jetzt = Date.now
        ringe.removeAll { jetzt.timeIntervalSince($0.geburt) > Rauch.ringDauer }
        platzer.removeAll { jetzt.timeIntervalSince($0.geburt) > Rauch.platzDauer }
        sprueche.removeAll { jetzt.timeIntervalSince($0.geburt) > Rauch.spruchDauer }
    }

    func leeren() {
        ringe = []
        platzer = []
        sprueche = []
    }

    /// Wo eine Wolke gerade ist, wie groß und wie sichtbar.
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

/// Umriss einer Rauchwolke: rundum Beulen mit kleinen Dellen dazwischen, die sich langsam verformen.
struct Wolke: Shape {
    var form: Rauch.Form
    var zeit: Double

    func path(in rect: CGRect) -> Path {
        let mitte = CGPoint(x: rect.midX, y: rect.midY)
        // Die Beulen ragen etwas über den Grundkreis hinaus – so passt alles in den Rahmen.
        let r0 = min(rect.width, rect.height) / 2 / 1.2
        let k = Double(form.buckel)
        var pfad = Path()
        let schritte = 96
        for i in 0..<schritte {
            let w = Double(i) / Double(schritte) * 2 * .pi
            let verzogen = w + form.verzug * sin(w + form.p1)
            var r = 1 + form.a2 * sin(2 * w + form.p2 + zeit * 0.5) + form.a3 * sin(3 * w + form.p3 - zeit * 0.4)
            let buckel = abs(sin(k * (verzogen + form.dreh + zeit * 0.12) / 2))
            r *= 0.8 + 0.2 * buckel.squareRoot()
            let p = CGPoint(x: mitte.x + r0 * CGFloat(r * cos(w) * form.streck),
                            y: mitte.y + r0 * CGFloat(r * sin(w) / form.streck))
            if i == 0 { pfad.move(to: p) } else { pfad.addLine(to: p) }
        }
        pfad.closeSubpath()
        return pfad
    }
}

/// Liegt über der ganzen Suche: zeigt Wolken und Sprüche. Leere Stellen lassen Berührungen durch.
struct RauchBild: View {
    var rauch: Rauch

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: rauch.istLeer)) { zeit in
                ZStack {
                    ForEach(rauch.ringe) { ring in
                        let z = Rauch.zustand(ring, jetzt: zeit.date)
                        let alter = zeit.date.timeIntervalSince(ring.geburt)
                        Wolke(form: ring.form, zeit: alter)
                            .stroke(Color.primary.opacity(0.55 * z.deckkraft),
                                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .background(Wolke(form: ring.form, zeit: alter).fill(Color.primary.opacity(0.04 * z.deckkraft)))
                            .frame(width: z.radius * 2.4, height: z.radius * 2.4)
                            .contentShape(Circle())
                            .position(z.ort)
                            .onTapGesture { rauch.antippen(ring) }
                    }
                    ForEach(rauch.platzer) { p in
                        PlatzerBild(platzer: p, jetzt: zeit.date)
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
                try? await Task.sleep(for: .seconds(0.5))
                rauch.aufraeumen()
            }
        }
    }
}

/// Zerplatzende Wolke: bläht sich kurz auf und zerfällt in kleine Fetzen, die davonstieben.
struct PlatzerBild: View {
    var platzer: Rauch.Platzer
    var jetzt: Date

    var body: some View {
        let f = min(1, jetzt.timeIntervalSince(platzer.geburt) / Rauch.platzDauer)
        let raus = 1 - (1 - f) * (1 - f)
        ZStack {
            Wolke(form: platzer.form, zeit: 0)
                .stroke(Color.primary.opacity(0.55 * max(0, 1 - f * 2.5)), lineWidth: 1.6)
                .frame(width: platzer.radius * 2.4, height: platzer.radius * 2.4)
                .scaleEffect(1 + 0.3 * raus)
            ForEach(Array(platzer.fetzen.enumerated()), id: \.offset) { i, w in
                let weite = (platzer.radius + 8) * CGFloat(0.6 + 0.7 * raus)
                Circle()
                    .stroke(Color.primary.opacity(0.5 * (1 - f)), lineWidth: 1.4)
                    .frame(width: CGFloat(5 + i % 3 * 2) * CGFloat(1 - 0.5 * f),
                           height: CGFloat(5 + i % 3 * 2) * CGFloat(1 - 0.5 * f))
                    .offset(x: weite * CGFloat(cos(w)), y: weite * CGFloat(sin(w)))
            }
        }
        .position(platzer.ort)
        .allowsHitTesting(false)
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
        // Im Bild halten, auch wenn die Wolke am Rand war
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
