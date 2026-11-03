import SwiftUI

/// „Janz weit draußen“: Die nächste Haltestelle ist mehr als 5 km weg.
struct JWDSeite: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            JWDBild()
                .frame(width: 320, height: 230)
            Text("JWD – dit tut weh")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

/// Strichzeichnung: Acker, schiefes Haltestellenschild, Kuh, rollender Steppenläufer.
struct JWDBild: View {
    var body: some View {
        TimelineView(.animation) { zeit in
            let t = zeit.date.timeIntervalSinceReferenceDate
            Canvas { ctx, groesse in
                let s = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                let papier = GraphicsContext.Shading.color(Color(.systemBackground))
                ctx.stroke(landschaft(groesse), with: .foreground, style: s)
                // Kuh und Schild decken die Ackerfurchen dahinter ab.
                let kuh = kuh(t: t)
                ctx.fill(kuh, with: papier)
                ctx.stroke(kuh, with: .foreground, style: s)
                let schild = schild()
                ctx.fill(schild, with: papier)
                ctx.stroke(schild, with: .foreground, style: s)
                ctx.draw(Text("H").font(.system(size: 15, weight: .heavy, design: .rounded)),
                       at: CGPoint(x: 101, y: 64))
                let knaeuel = steppenlaeufer(t: t, breite: groesse.width)
                ctx.stroke(knaeuel, with: .foreground, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
        .accessibilityLabel("Weit und breit keine Haltestelle")
    }

    private func landschaft(_ g: CGSize) -> Path {
        var p = Path()
        // Horizont mit sanftem Hügel
        p.move(to: CGPoint(x: 0, y: 128))
        p.addCurve(to: CGPoint(x: g.width, y: 124),
                   control1: CGPoint(x: 90, y: 112), control2: CGPoint(x: 200, y: 136))
        // Ackerfurchen laufen zum Fluchtpunkt
        let flucht = CGPoint(x: 170, y: 120)
        for unten in stride(from: -160.0, through: 480, by: 64) {
            let start = CGPoint(x: flucht.x + (unten - flucht.x) * 0.08, y: 131)
            p.move(to: start)
            p.addLine(to: CGPoint(x: unten, y: g.height))
        }
        // Schiefer Mast des Haltestellenschilds
        p.move(to: CGPoint(x: 88, y: 196)); p.addLine(to: CGPoint(x: 99, y: 80))
        // Sonne mit kurzen Strahlen
        let sonne = CGPoint(x: 278, y: 34)
        p.addEllipse(in: CGRect(x: sonne.x - 11, y: sonne.y - 11, width: 22, height: 22))
        for i in 0..<8 {
            let w = Double(i) * .pi / 4
            p.move(to: CGPoint(x: sonne.x + cos(w) * 16, y: sonne.y + sin(w) * 16))
            p.addLine(to: CGPoint(x: sonne.x + cos(w) * 22, y: sonne.y + sin(w) * 22))
        }
        // Eine Wolke
        p.move(to: CGPoint(x: 146, y: 48))
        p.addLine(to: CGPoint(x: 206, y: 48))
        p.addQuadCurve(to: CGPoint(x: 196, y: 34), control: CGPoint(x: 210, y: 36))
        p.addQuadCurve(to: CGPoint(x: 172, y: 26), control: CGPoint(x: 192, y: 18))
        p.addQuadCurve(to: CGPoint(x: 154, y: 34), control: CGPoint(x: 158, y: 22))
        p.addQuadCurve(to: CGPoint(x: 146, y: 48), control: CGPoint(x: 140, y: 38))
        return p
    }

    private func schild() -> Path {
        var p = Path()
        // Rundes Schild
        p.addEllipse(in: CGRect(x: 86, y: 50, width: 30, height: 30))
        // Fahrplankasten, leer
        p.addRoundedRect(in: CGRect(x: 80, y: 118, width: 22, height: 26), cornerSize: CGSize(width: 2, height: 2))
        p.move(to: CGPoint(x: 84, y: 125)); p.addLine(to: CGPoint(x: 97, y: 125))
        // Grasbüschel am Fuß
        for x in [78.0, 84, 92, 98] {
            p.move(to: CGPoint(x: x, y: 198)); p.addLine(to: CGPoint(x: x + 2, y: 189))
        }
        return p
    }

    private func kuh(t: Double) -> Path {
        var p = Path()
        let kauen = sin(t * 4) * 1.2
        // Körper
        p.addRoundedRect(in: CGRect(x: 196, y: 100, width: 64, height: 32), cornerSize: CGSize(width: 14, height: 14))
        // Flecken
        p.addEllipse(in: CGRect(x: 214, y: 106, width: 14, height: 10))
        p.addEllipse(in: CGRect(x: 238, y: 114, width: 11, height: 9))
        // Beine
        for x in [204.0, 214, 242, 252] {
            p.move(to: CGPoint(x: x, y: 131)); p.addLine(to: CGPoint(x: x, y: 154))
        }
        // Euter
        p.move(to: CGPoint(x: 226, y: 132)); p.addQuadCurve(to: CGPoint(x: 236, y: 132), control: CGPoint(x: 231, y: 140))
        // Schwanz
        let wedel = sin(t * 2.3) * 5
        p.move(to: CGPoint(x: 260, y: 106))
        p.addQuadCurve(to: CGPoint(x: 268 + wedel, y: 136), control: CGPoint(x: 274, y: 116))
        // Kopf, schaut zum Schild
        p.addRoundedRect(in: CGRect(x: 176, y: 92, width: 24, height: 20), cornerSize: CGSize(width: 8, height: 8))
        // Maul (kaut)
        p.addRoundedRect(in: CGRect(x: 172, y: 104 + kauen * 0.3, width: 16, height: 11 + kauen), cornerSize: CGSize(width: 5, height: 5))
        p.addEllipse(in: CGRect(x: 175.5, y: 108, width: 2, height: 2))
        p.addEllipse(in: CGRect(x: 181, y: 108, width: 2, height: 2))
        // Auge
        p.addEllipse(in: CGRect(x: 182, y: 97, width: 3, height: 3))
        // Hörner und Ohr
        p.move(to: CGPoint(x: 182, y: 92)); p.addQuadCurve(to: CGPoint(x: 178, y: 82), control: CGPoint(x: 176, y: 88))
        p.move(to: CGPoint(x: 194, y: 92)); p.addQuadCurve(to: CGPoint(x: 198, y: 82), control: CGPoint(x: 200, y: 88))
        p.move(to: CGPoint(x: 200, y: 96)); p.addLine(to: CGPoint(x: 208, y: 92)); p.addLine(to: CGPoint(x: 202, y: 102))
        // Sie steht vorne im Acker, nicht auf dem Horizont.
        return p.applying(CGAffineTransform(translationX: 0, y: 32))
    }

    private func steppenlaeufer(t: Double, breite: CGFloat) -> Path {
        let strecke = breite + 80
        let x = CGFloat((t * 34).truncatingRemainder(dividingBy: Double(strecke))) - 40
        let r: CGFloat = 13
        let y = 196 - r - abs(sin(Double(x) / 18)) * 7
        let dreh = Double(x) / Double(r)
        var p = Path()
        // Ein Knäuel aus versetzten Bögen
        for i in 0..<7 {
            let w = dreh + Double(i) * 0.9
            let rr = r * (0.55 + 0.45 * CGFloat((i % 3)) / 2)
            p.addArc(center: CGPoint(x: x + cos(w) * 2, y: y + sin(w) * 2), radius: rr,
                     startAngle: .radians(w), endAngle: .radians(w + 3.6), clockwise: false)
        }
        return p
    }
}

#Preview { JWDSeite() }
