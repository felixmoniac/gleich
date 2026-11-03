import SwiftUI

/// Strichkatze, die im Kreis rennt und sich in den Schwanz beißen will – der Schwanz ist eine kleine Lok,
/// immer knapp vor ihrer Nase. Steht in der Suche, solange dort noch nichts zu sehen ist.
struct KatzeImKreis: View {
    var body: some View {
        TimelineView(.animation) { zeit in
            let t = zeit.date.timeIntervalSinceReferenceDate
            Canvas { ctx, groesse in
                zeichnen(ctx, groesse: groesse, t: t)
            }
        }
        .frame(width: 230, height: 230)
        .accessibilityHidden(true)
    }

    private let r: CGFloat = 62
    private let strich = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)

    private func zeichnen(_ ctx: GraphicsContext, groesse: CGSize, t: Double) {
        var ctx = ctx
        ctx.translateBy(x: groesse.width / 2, y: groesse.height / 2)
        // Eine Runde in gut zwei Sekunden, mit kleinem Stolpern.
        let drehung = t * 2.7 + sin(t * 5.3) * 0.05
        ctx.rotate(by: .radians(drehung))

        // Körper: dicker, runder Bogen hinter dem Kopf – als Umriss (breiter Strich, innen ausgespart)
        var ruecken = Path()
        ruecken.addArc(center: .zero, radius: r, startAngle: .degrees(-100), endAngle: .degrees(-6), clockwise: false)
        ctx.stroke(ruecken, with: .foreground, style: StrokeStyle(lineWidth: 25, lineCap: .round))
        ctx.stroke(ruecken, with: .color(Color(.systemBackground)), style: StrokeStyle(lineWidth: 21.4, lineCap: .round))

        // Beine wirbeln: zwei Paare, außen am Kreis, mit kleinen Pfoten
        for (winkel, versatz) in [(-24.0, 0.0), (-84.0, .pi)] {
            ortlich(ctx, winkel: .degrees(winkel)) { c in
                var beine = Path()
                var pfoten = Path()
                let a = CGFloat(sin(t * 22 + versatz)) * 7
                for (y0, richtung) in [(CGFloat(4), CGFloat(1)), (CGFloat(-4), CGFloat(-1))] {
                    let ende = CGPoint(x: 26, y: y0 + a * richtung)
                    beine.move(to: CGPoint(x: 12, y: y0)); beine.addLine(to: ende)
                    pfoten.addEllipse(in: CGRect(x: ende.x - 1, y: ende.y - 2.5, width: 5, height: 5))
                }
                c.stroke(beine, with: .foreground, style: strich)
                c.stroke(pfoten, with: .foreground, style: StrokeStyle(lineWidth: 1.4))
            }
        }

        // Schwanz: läuft fast ganz herum und endet in der Lok vor der Nase
        let schwanzEnde = 312.0
        var schwanz = Path()
        let schritte = 40
        for i in 0...schritte {
            let f = Double(i) / Double(schritte)
            let w = (-100.0 - f * (schwanzEnde - 100.0)) * .pi / 180
            let wackel = CGFloat(sin(f * 12 + t * 9)) * 2.5 * CGFloat(f)
            let rr = r - 2 + wackel
            let p = CGPoint(x: cos(w) * rr, y: sin(w) * rr)
            if i == 0 { schwanz.move(to: p) } else { schwanz.addLine(to: p) }
        }
        ctx.stroke(schwanz, with: .foreground, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

        // Kleine Lok am Schwanzende (−312° = 48° vor dem Kopf), fährt in Laufrichtung
        ortlich(ctx, winkel: .degrees(-schwanzEnde)) { c in
            var c = c
            c.scaleBy(x: 1.6, y: 1.6)
            kleineLok(c, t: t)
        }

        // Kopf vorn, Blick in Laufrichtung, Ohren nach innen
        ortlich(ctx, winkel: .degrees(8)) { c in
            kopf(c, t: t)
        }
    }

    /// Zeichnet in einem Rahmen am Kreis: x zeigt nach außen, y in Laufrichtung.
    private func ortlich(_ ctx: GraphicsContext, winkel: Angle, _ zeichnen: (GraphicsContext) -> Void) {
        var c = ctx
        c.rotate(by: winkel)
        c.translateBy(x: r, y: 0)
        zeichnen(c)
    }

    private func kopf(_ c: GraphicsContext, t: Double) {
        let papier = GraphicsContext.Shading.color(Color(.systemBackground))
        // Ohren zeigen nach innen (−x), also „nach oben“
        var ohren = Path()
        for s in [CGFloat(-1), CGFloat(1)] {
            ohren.move(to: CGPoint(x: -9, y: s * 9)); ohren.addLine(to: CGPoint(x: -23, y: s * 10))
            ohren.addLine(to: CGPoint(x: -13, y: s * 1)); ohren.closeSubpath()
        }
        c.fill(ohren, with: papier)
        c.stroke(ohren, with: .foreground, style: strich)
        var k = Path()
        k.addEllipse(in: CGRect(x: -14, y: -13, width: 28, height: 27))
        c.fill(k, with: papier)
        c.stroke(k, with: .foreground, style: strich)
        // Gieriges Auge nach vorn, Schnauze mit Nase, Maul schnappt
        var auge = Path()
        auge.addEllipse(in: CGRect(x: -6, y: 2, width: 4, height: 4))
        c.fill(auge, with: .foreground)
        let schnapp = CGFloat(max(0, sin(t * 3.1))) * 3.5
        var gesicht = Path()
        gesicht.addEllipse(in: CGRect(x: 2, y: 9, width: 3, height: 3))
        gesicht.move(to: CGPoint(x: 3.5, y: 12)); gesicht.addLine(to: CGPoint(x: 7 + schnapp, y: 14))
        gesicht.move(to: CGPoint(x: 3.5, y: 12)); gesicht.addLine(to: CGPoint(x: 0 - schnapp, y: 14.5))
        // Schnurrhaare nach außen und vorn
        for (dx, dy) in [(7.0, 16.0), (11.0, 13.0), (12.0, 9.0)] {
            gesicht.move(to: CGPoint(x: 4, y: 10)); gesicht.addLine(to: CGPoint(x: 4 + dx, y: 10 + dy * 0.6))
        }
        c.stroke(gesicht, with: .foreground, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    /// Winzige Lok in Strichoptik, fährt in +y.
    private func kleineLok(_ c: GraphicsContext, t: Double) {
        var l = Path()
        // Kessel
        l.addRoundedRect(in: CGRect(x: -4, y: -2, width: 8, height: 13), cornerSize: CGSize(width: 4, height: 4))
        // Führerhaus hinten
        l.addRect(CGRect(x: -6, y: -10, width: 12, height: 9))
        // Schornstein vorn, nach innen (oben)
        l.move(to: CGPoint(x: -4, y: 7)); l.addLine(to: CGPoint(x: -9, y: 6)); l.addLine(to: CGPoint(x: -9, y: 10)); l.addLine(to: CGPoint(x: -4, y: 9))
        c.fill(l, with: .color(Color(.systemBackground)))
        c.stroke(l, with: .foreground, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        // Räder außen
        var raeder = Path()
        for y in [-6.0, 1.0, 7.0] {
            raeder.addEllipse(in: CGRect(x: 4, y: y - 2.5, width: 5, height: 5))
        }
        c.stroke(raeder, with: .foreground, style: StrokeStyle(lineWidth: 1.2))
        // Dampfwölkchen ziehen nach innen und zurück
        for i in 0..<3 {
            let p = (t * 1.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            var w = Path()
            let rr = 1.5 + p * 3.5
            w.addEllipse(in: CGRect(x: -11 - p * 10 - rr, y: 8 - p * 14 - rr, width: rr * 2, height: rr * 2))
            var cc = c
            cc.opacity = (1 - p) * 0.8
            cc.stroke(w, with: .foreground, style: StrokeStyle(lineWidth: 1.1))
        }
    }
}

#Preview { KatzeImKreis() }
