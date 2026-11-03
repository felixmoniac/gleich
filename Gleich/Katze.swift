import SwiftUI

/// Struppige Strichkatze, zu einem „C“ eingerollt, die ihren Schwanz jagen will – am Ende des kurzen, verdrehten
/// Schwanzes hängt eine kleine Lok, knapp vor ihrer Nase. Katze und Lok drehen sich gemeinsam im Kreis:
/// sanft anlaufen, ein, zwei Runden, auslaufen – und jedes Mal an einer anderen Stelle stehen bleiben.
/// Ein Tipp lässt sie noch einmal kurz rennen. Steht in der Suche, solange dort noch nichts zu sehen ist.
struct KatzeImKreis: View {
    /// Winkel, bei dem der aktuelle Lauf begann, und wie weit er führt (Bogenmaß).
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
                zeichnen(ctx, groesse: groesse, p: p, zeit: zeit.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: 250, height: 250)
        .contentShape(Rectangle())
        .onTapGesture { losrennen(kurz: true) }
        .accessibilityHidden(true)
        .task { losrennen(kurz: false) }
    }

    /// Neuer Lauf ab der Stelle, an der sie gerade ist; Länge zufällig, damit sie woanders stehen bleibt.
    private func losrennen(kurz: Bool) {
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
    }

    /// Langsam anlaufen, langsam auslaufen.
    private func sanft(_ p: Double) -> Double {
        p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    /// Momentane Geschwindigkeit des Laufs, 0 bis 1.
    private func tempo(_ p: Double) -> Double {
        (p < 0.5 ? 12 * p * p : 3 * pow(-2 * p + 2, 2)) / 3
    }

    private let r: CGFloat = 50
    private let strich = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
    private var papier: GraphicsContext.Shading { .color(Color(.systemBackground)) }

    /// Körper von hinten (Hinterteil) bis vorn (Hals); der Schwanz geht vom Hinterteil weiter nach hinten.
    private let hinten = -200.0, vorn = -2.0, schwanzEnde = -300.0

    private func zeichnen(_ ctx: GraphicsContext, groesse: CGSize, p: Double, zeit: Double) {
        let winkel = basis + strecke * sanft(p)
        let schwung = laeuft ? tempo(p) : 0
        // Beine und Maul hängen am zurückgelegten Weg – so werden sie mit ihr langsamer.
        let weg = winkel * 6

        var ctx = ctx
        ctx.translateBy(x: groesse.width / 2, y: groesse.height / 2)
        ctx.rotate(by: .radians(winkel))

        schwanz(ctx, t: weg, schwung: schwung)
        ortlich(ctx, winkel: .degrees(schwanzEnde + 360)) { c in
            var c = c
            c.scaleBy(x: 1.7, y: 1.7)
            kleineLok(c, t: zeit, schwung: schwung)
        }
        beine(ctx, t: weg, schwung: schwung)
        koerper(ctx)
        ortlich(ctx, winkel: .degrees(10)) { c in
            kopf(c, t: weg, schwung: schwung)
        }
    }

    /// Zeichnet in einem Rahmen am Kreis: x zeigt nach außen, y in Laufrichtung.
    private func ortlich(_ ctx: GraphicsContext, winkel: Angle, _ zeichnen: (GraphicsContext) -> Void) {
        var c = ctx
        c.rotate(by: winkel)
        c.translateBy(x: r, y: 0)
        zeichnen(c)
    }

    private func punkt(_ grad: Double, _ radius: CGFloat) -> CGPoint {
        let w = grad * .pi / 180
        return CGPoint(x: cos(w) * radius, y: sin(w) * radius)
    }

    /// Immer gleiche „Zufallszahl“ zwischen 0 und 1 – damit das Fell unregelmäßig, aber ruhig aussieht.
    private func zufall(_ i: Int) -> CGFloat {
        let x = sin(Double(i) * 12.9898) * 43758.5453
        return CGFloat(x - x.rounded(.down))
    }

    /// Zotteliges Fell: außen unregelmäßige Büschel, hinten ein rundes Hinterteil, innen kurze Zacken.
    private func koerper(_ ctx: GraphicsContext) {
        var fell = Path()
        let von = hinten, bis = vorn
        // Hinterteil: von innen über hinten nach außen um das Körperende herum
        let rumpfMitte = punkt(von, r)
        let rumpf = 13
        for i in 0...rumpf {
            let a = (von + 180 + 180 * Double(i) / Double(rumpf)) * .pi / 180
            let rr: CGFloat = i % 2 == 0 ? 12 + zufall(i + 50) * 3 : 9 + zufall(i + 70) * 2
            let p = CGPoint(x: rumpfMitte.x + cos(a) * rr, y: rumpfMitte.y + sin(a) * rr)
            if i == 0 { fell.move(to: p) } else { fell.addLine(to: p) }
        }
        // Rücken außen: lange und kurze Büschel durcheinander
        let n = 52
        for i in 1...n {
            let g = von + (bis - von) * Double(i) / Double(n)
            let zacke: CGFloat = i % 2 == 0 ? 10 + zufall(i) * 5 : 7 + zufall(i + 100) * 2
            fell.addLine(to: punkt(g + Double(zufall(i + 200) - 0.5) * 2, r + zacke))
        }
        // Bauch innen: kleine Zacken zurück nach hinten
        for i in stride(from: n, through: 0, by: -1) {
            let g = von + (bis - von) * Double(i) / Double(n)
            let zacke: CGFloat = i % 2 == 0 ? 9 + zufall(i + 300) * 2 : 7
            fell.addLine(to: punkt(g, r - zacke))
        }
        fell.closeSubpath()
        ctx.fill(fell, with: papier)
        ctx.stroke(fell, with: .foreground, style: strich)
        // Ein paar Fellstriche im Inneren, wie hingekritzelt
        var striche = Path()
        for (j, g) in stride(from: hinten + 10, through: vorn - 16, by: 15).enumerated() {
            let lang = 4 + zufall(j + 400) * 5
            striche.move(to: punkt(g, r + 1 + zufall(j + 500) * 3)); striche.addLine(to: punkt(g + 4, r + 1 + lang))
        }
        ctx.stroke(striche, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    private func beine(_ ctx: GraphicsContext, t: Double, schwung: Double) {
        for (winkel, versatz) in [(-34.0, 0.0), (-165.0, Double.pi)] {
            ortlich(ctx, winkel: .degrees(winkel)) { c in
                var beine = Path()
                var pfoten = Path()
                let a = CGFloat(sin(t * 22 + versatz) * schwung) * 8
                for (y0, richtung) in [(CGFloat(5), CGFloat(1)), (CGFloat(-5), CGFloat(-1))] {
                    let ende = CGPoint(x: 28, y: y0 + a * richtung)
                    beine.move(to: CGPoint(x: 13, y: y0)); beine.addLine(to: ende)
                    pfoten.addEllipse(in: CGRect(x: ende.x - 2, y: ende.y - 4, width: 8, height: 8))
                }
                c.stroke(beine, with: .foreground, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                c.fill(pfoten, with: papier)
                c.stroke(pfoten, with: .foreground, style: StrokeStyle(lineWidth: 2))
            }
        }
    }

    /// Normal langer Schwanz mit einem Kringel (einer kleinen Schlinge) in der Mitte; an seinem Ende hängt die Lok.
    private func schwanz(_ ctx: GraphicsContext, t: Double, schwung: Double) {
        var s = Path()
        let knick = 0.4
        func bogen(_ f: Double) -> CGPoint {
            // Leicht gewellt, wackelt beim Rennen
            let welle = CGFloat(sin(f * 7 + t * 0.8 * schwung)) * 3 * CGFloat(sin(f * .pi))
            return punkt(hinten + (schwanzEnde - hinten) * f, r + welle)
        }
        for i in 0...24 { let p = bogen(knick * Double(i) / 24); i == 0 ? s.move(to: p) : s.addLine(to: p) }
        // Die Schlinge: einmal rundherum, nach außen gestellt
        let g = (hinten + (schwanzEnde - hinten) * knick) * .pi / 180
        let anfang = bogen(knick)
        let schlinge: CGFloat = 9
        let mitte = CGPoint(x: anfang.x + CGFloat(cos(g)) * schlinge, y: anfang.y + CGFloat(sin(g)) * schlinge)
        for i in 1...28 {
            let a = g + .pi - 2 * .pi * Double(i) / 28
            s.addLine(to: CGPoint(x: mitte.x + CGFloat(cos(a)) * schlinge, y: mitte.y + CGFloat(sin(a)) * schlinge))
        }
        for i in 1...30 { s.addLine(to: bogen(knick + (1 - knick) * Double(i) / 30)) }
        ctx.stroke(s, with: .foreground, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
    }

    /// Großer, struppiger Kopf mit großen runden Augen, die auf die Lok starren.
    private func kopf(_ c: GraphicsContext, t: Double, schwung: Double) {
        // Ohren zeigen nach innen (−x), also „nach oben“
        var ohren = Path()
        for s in [CGFloat(-1), CGFloat(1)] {
            ohren.move(to: CGPoint(x: -12, y: s * 13)); ohren.addLine(to: CGPoint(x: -30, y: s * 14))
            ohren.addLine(to: CGPoint(x: -18, y: s * 2)); ohren.closeSubpath()
        }
        c.fill(ohren, with: papier)
        c.stroke(ohren, with: .foreground, style: strich)

        // Zottiger Umriss: abwechselnd lange und kurze Zacken
        var k = Path()
        let n = 22
        for i in 0..<n {
            let w = Double(i) / Double(n) * 2 * .pi
            let rr: CGFloat = i % 2 == 0 ? 21 + zufall(i + 600) * 5 : 17 + zufall(i + 700) * 2
            let p = CGPoint(x: cos(w) * rr, y: sin(w) * rr)
            if i == 0 { k.move(to: p) } else { k.addLine(to: p) }
        }
        k.closeSubpath()
        c.fill(k, with: papier)
        c.stroke(k, with: .foreground, style: strich)

        // Große Augen nebeneinander, Pupillen schauen nach vorn zur Lok
        var augen = Path()
        var pupillen = Path()
        for x in [CGFloat(-7), CGFloat(7)] {
            augen.addEllipse(in: CGRect(x: x - 6.5, y: -1, width: 13, height: 14))
            pupillen.addEllipse(in: CGRect(x: x - 2, y: 7, width: 4.5, height: 4.5))
        }
        c.fill(augen, with: papier)
        c.stroke(augen, with: .foreground, style: strich)
        c.fill(pupillen, with: .foreground)

        // Kleine Nase und Maul; beim Rennen schnappt es, am Ende ist es zu
        let schnapp = CGFloat(max(0, sin(t * 3.4)) * schwung) * 4
        var gesicht = Path()
        gesicht.move(to: CGPoint(x: -2, y: 15)); gesicht.addLine(to: CGPoint(x: 2, y: 15)); gesicht.addLine(to: CGPoint(x: 0, y: 17.5))
        gesicht.closeSubpath()
        gesicht.move(to: CGPoint(x: 0, y: 17.5)); gesicht.addQuadCurve(to: CGPoint(x: -4, y: 20 + schnapp), control: CGPoint(x: -1, y: 20 + schnapp))
        gesicht.move(to: CGPoint(x: 0, y: 17.5)); gesicht.addQuadCurve(to: CGPoint(x: 4, y: 20 + schnapp), control: CGPoint(x: 1, y: 20 + schnapp))
        // Schnurrhaare, keck abstehend
        for s in [CGFloat(-1), CGFloat(1)] {
            for (dx, dy) in [(CGFloat(14), CGFloat(3)), (CGFloat(15), CGFloat(8))] {
                gesicht.move(to: CGPoint(x: s * 9, y: 16)); gesicht.addLine(to: CGPoint(x: s * (9 + dx), y: 16 + dy))
            }
        }
        c.stroke(gesicht, with: .foreground, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    /// Winzige Lok in Strichoptik, fährt in +y.
    private func kleineLok(_ c: GraphicsContext, t: Double, schwung: Double) {
        var l = Path()
        l.addRoundedRect(in: CGRect(x: -4, y: -2, width: 8, height: 13), cornerSize: CGSize(width: 4, height: 4))
        l.addRect(CGRect(x: -6, y: -10, width: 12, height: 9))
        l.move(to: CGPoint(x: -4, y: 7)); l.addLine(to: CGPoint(x: -9, y: 6)); l.addLine(to: CGPoint(x: -9, y: 10)); l.addLine(to: CGPoint(x: -4, y: 9))
        c.fill(l, with: papier)
        c.stroke(l, with: .foreground, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        var raeder = Path()
        for y in [-6.0, 1.0, 7.0] {
            raeder.addEllipse(in: CGRect(x: 4, y: y - 2.5, width: 5, height: 5))
        }
        c.stroke(raeder, with: .foreground, style: StrokeStyle(lineWidth: 1.1))
        // Dampf nur, solange sie fährt
        guard schwung > 0.05 else { return }
        for i in 0..<3 {
            let p = (t * 1.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            var w = Path()
            let rr = 1.5 + p * 3.5
            w.addEllipse(in: CGRect(x: -11 - p * 10 - rr, y: 8 - p * 14 - rr, width: rr * 2, height: rr * 2))
            var cc = c
            cc.opacity = (1 - p) * 0.8 * schwung
            cc.stroke(w, with: .foreground, style: StrokeStyle(lineWidth: 1))
        }
    }
}

#Preview { KatzeImKreis() }
