import SwiftUI

/// Kleine Dampflok in Strichoptik. Fährt nach rechts.
/// `ruckelt`: tuckert auf der Stelle (hüpft, wackelt, dampft).
/// `strecke`: zurückgelegter Weg in Punkten – dreht die Räder beim Hereinrollen.
struct Lok: View {
    var ruckelt: Bool
    var strecke: CGFloat = 0

    static let groesse = CGSize(width: 76, height: 74)

    var body: some View {
        if ruckelt {
            TimelineView(.animation) { zeit in
                zeichnung(t: zeit.date.timeIntervalSinceReferenceDate)
            }
        } else {
            zeichnung(t: nil)
        }
    }

    private func zeichnung(t: Double?) -> some View {
        Canvas { ctx, _ in
            // Oben Platz für den Dampf lassen.
            var ctx = ctx
            ctx.translateBy(x: 0, y: 16)
            let t = t ?? 0
            let laeuft = ruckelt
            // Huckeln, Buckeln, Ruckeln – absichtlich unregelmäßig.
            let hupf = laeuft ? -abs(sin(t * 11)) * 2.2 - max(0, sin(t * 3.7)) * 1.2 : 0
            let kipp = laeuft ? sin(t * 6.5) * 0.05 + sin(t * 15.3) * 0.015 : 0
            let ruck = laeuft ? sin(t * 17) * 0.6 : 0
            let winkel = laeuft ? t * 9 : Double(strecke) / 7

            // Dampf zuerst, damit die Lok davor steht.
            if laeuft { dampf(ctx, t: t, hupf: hupf) }

            var lok = ctx
            lok.translateBy(x: 38 + ruck, y: 50 + hupf)
            lok.rotate(by: .radians(kipp))
            lok.translateBy(x: -38, y: -50)
            Lok.koerper(lok, winkel: winkel)
        }
        .frame(width: Lok.groesse.width, height: Lok.groesse.height)
        .accessibilityHidden(true)
    }

    private static let strich = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)

    /// Die Lok selbst, ohne Dampf: fährt nach rechts (+x), Schornstein oben (−y), Räder unten bei y ≈ 54.
    /// Auch die Katze in der Suche nimmt genau diese Lok.
    static func koerper(_ ctx: GraphicsContext, winkel: Double) {
        var p = Path()
        // Kessel mit runder Rauchkammer vorne
        p.addRoundedRect(in: CGRect(x: 30, y: 28, width: 34, height: 14), cornerSize: CGSize(width: 7, height: 7))
        // Führerhaus mit Fenster und überstehendem Dach
        p.addRect(CGRect(x: 10, y: 18, width: 20, height: 24))
        p.addRoundedRect(in: CGRect(x: 15, y: 22, width: 10, height: 8), cornerSize: CGSize(width: 2, height: 2))
        p.move(to: CGPoint(x: 6, y: 18)); p.addQuadCurve(to: CGPoint(x: 34, y: 18), control: CGPoint(x: 20, y: 12))
        // Schornstein als Trichter
        p.move(to: CGPoint(x: 55, y: 28)); p.addLine(to: CGPoint(x: 53, y: 17))
        p.move(to: CGPoint(x: 61, y: 28)); p.addLine(to: CGPoint(x: 63, y: 17))
        p.move(to: CGPoint(x: 51.5, y: 16.5)); p.addLine(to: CGPoint(x: 64.5, y: 16.5))
        // Dom
        p.move(to: CGPoint(x: 38, y: 28)); p.addQuadCurve(to: CGPoint(x: 46, y: 28), control: CGPoint(x: 42, y: 20))
        // Rahmen, Puffer, Schienenräumer
        p.move(to: CGPoint(x: 7, y: 42)); p.addLine(to: CGPoint(x: 66, y: 42))
        p.move(to: CGPoint(x: 3, y: 39)); p.addLine(to: CGPoint(x: 7, y: 39))
        p.move(to: CGPoint(x: 64, y: 42)); p.addLine(to: CGPoint(x: 71, y: 51)); p.addLine(to: CGPoint(x: 62, y: 51))
        ctx.stroke(p, with: .foreground, style: strich)

        // Räder mit Speichen und Kuppelstange
        let raeder: [(CGPoint, CGFloat)] = [(CGPoint(x: 21, y: 46), 8.5), (CGPoint(x: 42, y: 48.5), 6), (CGPoint(x: 56, y: 48.5), 6)]
        var r = Path()
        for (mitte, radius) in raeder {
            r.addEllipse(in: CGRect(x: mitte.x - radius, y: mitte.y - radius, width: radius * 2, height: radius * 2))
            for i in 0..<3 {
                let w = winkel + Double(i) * .pi / 3
                let dx = cos(w) * radius * 0.8, dy = sin(w) * radius * 0.8
                r.move(to: CGPoint(x: mitte.x - dx, y: mitte.y - dy))
                r.addLine(to: CGPoint(x: mitte.x + dx, y: mitte.y + dy))
            }
        }
        ctx.stroke(r, with: .foreground, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        var stange = Path()
        let kurbel = CGPoint(x: cos(winkel) * 3.5, y: sin(winkel) * 3.5)
        stange.move(to: CGPoint(x: 21 + kurbel.x * 1.3, y: 46 + kurbel.y * 1.3))
        stange.addLine(to: CGPoint(x: 42 + kurbel.x, y: 48.5 + kurbel.y))
        stange.addLine(to: CGPoint(x: 56 + kurbel.x, y: 48.5 + kurbel.y))
        ctx.stroke(stange, with: .foreground, style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func dampf(_ ctx: GraphicsContext, t: Double, hupf: Double) {
        for i in 0..<4 {
            let phase = (t * 1.4 + Double(i) / 4).truncatingRemainder(dividingBy: 1)
            let x = 58 - phase * 34 + sin(phase * 9 + Double(i)) * 2
            let y = 14 + hupf * (1 - phase) - phase * 15
            let r = 2.5 + phase * 6.5
            var w = Path()
            // Drei überlappende Kreise ergeben eine Wolke.
            w.addEllipse(in: CGRect(x: x - r, y: y - r * 0.8, width: r * 2, height: r * 1.6))
            w.addEllipse(in: CGRect(x: x - r * 1.6, y: y - r * 0.3, width: r * 1.3, height: r * 1.1))
            w.addEllipse(in: CGRect(x: x + r * 0.4, y: y - r * 0.2, width: r * 1.2, height: r))
            var c = ctx
            c.opacity = (1 - phase) * 0.85
            c.stroke(w, with: .foreground, style: StrokeStyle(lineWidth: 1.3))
        }
    }
}

/// Scrollbereich mit eigenem „Runterziehen zum Aktualisieren“: Statt eines Kreisels rollt die Lok herein,
/// tuckert, solange geladen wird, und dampft danach rechts davon.
struct LokScroll<Inhalt: View>: View {
    var laedt: Bool
    var aktualisieren: () async -> Void
    @ViewBuilder var inhalt: () -> Inhalt

    private enum Phase { case ruhe, laden, abfahrt }
    @State private var phase: Phase = .ruhe
    @State private var zug: CGFloat = 0
    @State private var weg: CGFloat = 0
    @State private var start = Date.distantPast
    @State private var lokBreite: CGFloat = 400

    /// Ab hier lädt Loslassen neu.
    private let schwelle: CGFloat = 100
    /// Ab dieser Lücke passt die ganze Lok hinein (ohne Dampf).
    private let platz: CGFloat = 52
    private let hoehe: CGFloat = 84

    var body: some View {
        GeometryReader { geo in
            let breite = geo.size.width
            ScrollView {
                VStack(spacing: 0) {
                    ZStack {
                        if phase != .ruhe {
                            Lok(ruckelt: true)
                                .offset(x: weg)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: phase == .ruhe ? 0 : hoehe)
                    inhalt()
                }
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { g in
                -(g.contentOffset.y + g.contentInsets.top)
            } action: { _, neu in
                zug = max(0, neu)
            }
            .onScrollPhaseChange { alt, neu in
                if alt == .interacting, neu != .interacting, zug >= schwelle, phase == .ruhe {
                    losfahren()
                }
            }
            .overlay(alignment: .top) {
                // Beim Ziehen rollt die Lok von links herein – erst, wenn die Lücke über der Liste groß genug
                // für die ganze Lok ist. Sie steht auf dem unteren Rand der Lücke und fährt nie über die Abfahrten.
                if phase == .ruhe, zug >= platz {
                    let anteil = min((zug - platz) / (schwelle - platz), 1)
                    let x = -(breite / 2 + 50) * (1 - anteil)
                    Lok(ruckelt: false, strecke: x)
                        .offset(x: x)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .frame(height: zug)
                        .clipped()
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: laedt, initial: true) { _, l in
                if l, phase == .ruhe {
                    weg = 0
                    start = .now
                    phase = .laden
                } else if !l, phase == .laden {
                    abfahren(breite: breite)
                }
            }
            .onChange(of: breite, initial: true) { _, b in lokBreite = b }
        }
    }

    private func losfahren() {
        weg = 0
        start = .now
        withAnimation(.snappy) { phase = .laden }
        Task {
            await aktualisieren()
            await MainActor.run { if !laedt { abfahren(breite: lokBreite) } }
        }
    }

    private func abfahren(breite: CGFloat) {
        guard phase == .laden else { return }
        // Die Lok soll man wenigstens kurz tuckern sehen.
        let rest = max(0, 0.9 - Date.now.timeIntervalSince(start))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(rest))
            guard phase == .laden, !laedt else { return }
            phase = .abfahrt
            withAnimation(.easeIn(duration: 0.75)) { weg = breite / 2 + 60 }
            try? await Task.sleep(for: .seconds(0.75))
            withAnimation(.smooth(duration: 0.3)) { phase = .ruhe }
            weg = 0
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        Lok(ruckelt: true).scaleEffect(3)
        Lok(ruckelt: false).scaleEffect(3)
    }
}
