import SwiftUI

/// Kleiner Strichzug auf einem runden Gleis: vorne die Lok, dahinter vier Wagen. Er fährt im Kreis – sanft anlaufen,
/// ein, zwei Runden, auslaufen – und bleibt jedes Mal an einer anderen Stelle stehen. Beim Fahren stößt die Lok
/// Wölkchen aus. Ein Tipp lässt ihn noch einmal kurz fahren. Steht in der Suche, solange dort noch nichts zu sehen ist.
struct ZugImKreis: View {
    var rauch: Rauch
    /// Wo der Zug im Raum „suche“ steht – damit die Wölkchen am Schornstein starten.
    @State private var rahmen = CGRect.zero
    /// Winkel, bei dem die aktuelle Fahrt begann, und wie weit sie führt (Bogenmaß).
    @State private var basis = Double.random(in: 0..<(2 * .pi))
    @State private var strecke = 0.0
    @State private var start = Date.now
    @State private var dauer = 4.0
    @State private var laeuft = false
    @State private var lauf = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !laeuft)) { zeit in
            let p = laeuft ? min(1, zeit.date.timeIntervalSince(start) / dauer) : 1
            Canvas { ctx, groesse in
                zeichnen(ctx, groesse: groesse, p: p)
            }
        }
        .frame(width: 250, height: 250)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("suche")) } action: { rahmen = $0 }
        .contentShape(Rectangle())
        .onTapGesture { losfahren(kurz: true) }
        .accessibilityHidden(true)
        .task { losfahren(kurz: false) }
        // Verschwindet er (es wird gesucht), hört auch der Dampf sofort auf.
        .onDisappear { lauf += 1; laeuft = false }
    }

    /// Neue Fahrt ab der Stelle, an der er gerade ist; Länge zufällig, damit er woanders stehen bleibt.
    private func losfahren(kurz: Bool) {
        if laeuft {
            let p = min(1, Date.now.timeIntervalSince(start) / dauer)
            basis += strecke * sanft(p)
        } else {
            basis += strecke
        }
        strecke = 2 * .pi * (kurz ? Double.random(in: 0.8...1.5) : Double.random(in: 1.4...2.4))
        dauer = kurz ? 2.6 : 4.2
        start = .now
        laeuft = true
        lauf += 1
        let meiner = lauf
        Task {
            try? await Task.sleep(for: .seconds(dauer + 0.1))
            if lauf == meiner { laeuft = false }
        }
        // Wölkchen, solange er in Fahrt ist
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            while lauf == meiner, laeuft {
                let p = min(1, Date.now.timeIntervalSince(start) / dauer)
                if tempo(p) > 0.15 {
                    rauch.ausstossen(bei: schornstein(winkel: basis + strecke * sanft(p)),
                                     weg: CGPoint(x: rahmen.midX, y: rahmen.midY))
                }
                try? await Task.sleep(for: .seconds(0.38))
            }
        }
    }

    /// Wo der Schornstein gerade ist, im Raum „suche“.
    private func schornstein(winkel: Double) -> CGPoint {
        // Schornsteinöffnung der Lok liegt bei (58, 16,5); verschoben, gedreht und verkleinert wie unten.
        let lokal = CGPoint(x: r + (54 - 16.5) * massstab, y: (58 - 37) * massstab)
        return CGPoint(x: rahmen.midX + lokal.x * cos(winkel) - lokal.y * sin(winkel),
                       y: rahmen.midY + lokal.x * sin(winkel) + lokal.y * cos(winkel))
    }

    /// Langsam anlaufen, langsam auslaufen.
    private func sanft(_ p: Double) -> Double {
        p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    /// Momentane Geschwindigkeit der Fahrt, 0 bis 1.
    private func tempo(_ p: Double) -> Double {
        (p < 0.5 ? 12 * p * p : 3 * pow(-2 * p + 2, 2)) / 3
    }

    /// Halbmesser des Gleises; die Räder stehen darauf, Lok und Wagen außen.
    private let r: CGFloat = 60
    private let massstab: CGFloat = 0.86
    private let wagen = 4
    /// Länge eines Wagens samt Puffern (in Lok-Maßen) und Abstand dazwischen.
    private let wagenLaenge: CGFloat = 44
    private let kupplung: CGFloat = 3
    private static let strich = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
    private var papier: GraphicsContext.Shading { .color(Color(.systemBackground)) }

    private func zeichnen(_ ctx: GraphicsContext, groesse: CGSize, p: Double) {
        let winkel = basis + strecke * sanft(p)
        // Räder drehen sich mit dem zurückgelegten Weg – so werden sie mit dem Zug langsamer.
        let rad = winkel * 18

        var ctx = ctx
        ctx.translateBy(x: groesse.width / 2, y: groesse.height / 2)
        gleis(ctx)
        ctx.rotate(by: .radians(winkel))

        // Wagen von hinten nach vorn, jeweils als Sehne auf dem Kreis, damit beide Achsen auf dem Gleis stehen.
        // Die Lok fährt in Richtung wachsender Winkel; die Wagen hängen dahinter.
        let lokHinten = 34 * massstab
        let l = wagenLaenge * massstab
        for i in stride(from: wagen - 1, through: 0, by: -1) {
            let abstand = lokHinten + kupplung + l / 2 + CGFloat(i) * (l + kupplung)
            let mitte = -Double(abstand / r)
            let halb = asin(Double(l / 2 / r))
            var c = ctx
            c.rotate(by: .radians(mitte))
            c.translateBy(x: r * CGFloat(cos(halb)), y: 0)
            c.scaleBy(x: massstab, y: massstab)
            c.rotate(by: .degrees(90))
            c.translateBy(x: -wagenLaenge / 2, y: -54.5)
            ZugImKreis.wagen(c, winkel: rad, papier: papier)
        }

        // Dieselbe Lok wie beim Herunterziehen. Räder auf dem Gleis, Schornstein außen.
        var c = ctx
        c.translateBy(x: r, y: 0)
        c.scaleBy(x: massstab, y: massstab)
        c.rotate(by: .degrees(90))
        c.translateBy(x: -37, y: -54)
        var hinten = Path()
        hinten.addRect(CGRect(x: 10, y: 18, width: 20, height: 24))
        hinten.addRoundedRect(in: CGRect(x: 30, y: 28, width: 34, height: 14), cornerSize: CGSize(width: 7, height: 7))
        c.fill(hinten, with: papier)
        Lok.koerper(c, winkel: rad)
    }

    /// Ein schmales rundes Gleis mit kurzen Schwellen nach innen.
    private func gleis(_ ctx: GraphicsContext) {
        var g = Path()
        g.addEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
        for i in 0..<36 {
            let w = Double(i) / 36 * 2 * .pi
            g.move(to: CGPoint(x: cos(w) * r, y: sin(w) * r))
            g.addLine(to: CGPoint(x: cos(w) * (r - 5), y: sin(w) * (r - 5)))
        }
        var c = ctx
        c.opacity = 0.5
        c.stroke(g, with: .foreground, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    /// Ein Personenwagen im Stil der Lok: fährt nach rechts (+x), Dach oben (−y), Räder unten bei y ≈ 54,5.
    static func wagen(_ ctx: GraphicsContext, winkel: Double, papier: GraphicsContext.Shading) {
        var kasten = Path()
        kasten.addRoundedRect(in: CGRect(x: 4, y: 24, width: 36, height: 18), cornerSize: CGSize(width: 2, height: 2))
        ctx.fill(kasten, with: papier)

        var p = kasten
        // Gewölbtes Dach mit kleinem Überstand
        p.move(to: CGPoint(x: 2, y: 24)); p.addQuadCurve(to: CGPoint(x: 42, y: 24), control: CGPoint(x: 22, y: 16))
        // Drei Fenster
        for x in [CGFloat(8), 19, 30] {
            p.addRoundedRect(in: CGRect(x: x, y: 28, width: 7, height: 7), cornerSize: CGSize(width: 1.5, height: 1.5))
        }
        // Rahmen und Puffer vorn und hinten
        p.move(to: CGPoint(x: 3, y: 42)); p.addLine(to: CGPoint(x: 41, y: 42))
        p.move(to: CGPoint(x: 0, y: 39)); p.addLine(to: CGPoint(x: 4, y: 39))
        p.move(to: CGPoint(x: 40, y: 39)); p.addLine(to: CGPoint(x: 44, y: 39))
        ctx.stroke(p, with: .foreground, style: strich)

        // Zwei Räder mit Speichen
        var r = Path()
        for mitte in [CGPoint(x: 11, y: 48.5), CGPoint(x: 33, y: 48.5)] {
            let radius: CGFloat = 6
            r.addEllipse(in: CGRect(x: mitte.x - radius, y: mitte.y - radius, width: radius * 2, height: radius * 2))
            for i in 0..<3 {
                let w = winkel + Double(i) * .pi / 3
                let dx = cos(w) * radius * 0.8, dy = sin(w) * radius * 0.8
                r.move(to: CGPoint(x: mitte.x - dx, y: mitte.y - dy))
                r.addLine(to: CGPoint(x: mitte.x + dx, y: mitte.y + dy))
            }
        }
        ctx.fill(r, with: papier)
        ctx.stroke(r, with: .foreground, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }
}

#Preview { ZugImKreis(rauch: Rauch()) }
