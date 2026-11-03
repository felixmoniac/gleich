import SwiftUI
import Observation
import UIKit

/// „Wollalarm“ – das versteckte Spiel: Die kleine Lok fährt unten hin und her und pustet Dampfwolken nach oben.
/// Von oben rückt eine Formation struppiger Katzen an, wirft Wollknäuel und wird schneller, je weniger übrig sind.
/// Prellböcke geben Deckung, ab und zu saust ein Kontrolleur vorbei.
@Observable
final class Wollalarm {
    enum Phase { case start, laeuft, ende }

    struct Katze {
        var spalte: Int
        var reihe: Int
        var lebt = true
    }

    struct Prellbock {
        var ursprung: CGPoint
        var zellen: [[Bool]]
    }

    struct Blitz {
        var ort: CGPoint
        var zeit: Double
        var gross: Bool
    }

    static let spalten = 9, reihen = 5
    static let zelle: CGFloat = 3

    var phase: Phase = .start
    var feld = CGSize(width: 390, height: 700)
    private(set) var zeit = 0.0
    private(set) var punkte = 0
    private(set) var rekord = UserDefaults.standard.integer(forKey: "wollalarm.rekord")
    private(set) var leben = 3
    private(set) var welle = 0
    private(set) var lokX: CGFloat = 195
    /// Stellung der Wippe: −1 ganz links, 0 steht, +1 ganz rechts – dazwischen stufenlos.
    var steuer: CGFloat = 0
    private(set) var lokWeg = 0.0
    private(set) var unverwundbarBis = 0.0
    /// Dampfwolken unterwegs nach oben.
    private(set) var schuesse: [CGPoint] = []
    /// Wird die Dampftaste gehalten, pustet die Lok fortlaufend.
    var dampfGehalten = false
    private var naechsterSchuss = 0.0
    /// Abstand zwischen zwei Wolken beim Dauerfeuer.
    static let schussTakt = 0.2
    private(set) var katzen: [Katze] = []
    private(set) var versatz = CGPoint.zero
    private var richtung: CGFloat = 1
    private var takt = 0.0
    private(set) var bild = false
    private(set) var knaeuel: [CGPoint] = []
    private var naechsterWurf = 1.2
    private(set) var prellboecke: [Prellbock] = []
    private(set) var kontrolleur: CGPoint?
    private var kontrolleurRichtung: CGFloat = 1
    private var naechsterKontrolleur = 18.0
    private(set) var blitze: [Blitz] = []
    private(set) var bonus: (text: String, ort: CGPoint, zeit: Double)?

    // MARK: Maße

    var abstandX: CGFloat { min(40, feld.width * 0.09) }
    let abstandY: CGFloat = 30
    /// Unten bleibt Platz für die Tasten.
    var lokY: CGFloat { feld.height - 150 }
    var schornsteinX: CGFloat { lokX + (58 - 37) * 0.7 }

    func ort(_ k: Katze) -> CGPoint {
        let breite = CGFloat(Wollalarm.spalten - 1) * abstandX
        return CGPoint(x: (feld.width - breite) / 2 + versatz.x + CGFloat(k.spalte) * abstandX,
                       y: 110 + versatz.y + CGFloat(k.reihe) * abstandY)
    }

    static func wert(reihe: Int) -> Int { reihe == 0 ? 30 : (reihe < 3 ? 20 : 10) }

    // MARK: Ablauf

    /// Dampftaste gedrückt: schießt sofort (oder startet ein neues Spiel), danach Dauerfeuer bis zum Loslassen.
    func dampf(gedrueckt: Bool) {
        dampfGehalten = gedrueckt
        guard gedrueckt else { return }
        if phase == .laeuft { feuern() } else { neuesSpiel() }
    }

    /// Tipp aufs Spielfeld startet nur, schießt aber nicht.
    func starten() {
        if phase != .laeuft { neuesSpiel() }
    }

    private func neuesSpiel() {
        punkte = 0
        leben = 3
        welle = 0
        lokX = feld.width / 2
        unverwundbarBis = 0
        bonus = nil
        blitze = []
        kontrolleur = nil
        naechsterKontrolleur = .random(in: 15...25)
        prellboecke = Wollalarm.bauePrellboecke(breite: feld.width, y: lokY - 78)
        neueWelle()
        phase = .laeuft
    }

    private func neueWelle() {
        katzen = (0..<Wollalarm.reihen).flatMap { r in (0..<Wollalarm.spalten).map { Katze(spalte: $0, reihe: r) } }
        // Jede Welle startet ein Stück tiefer
        versatz = CGPoint(x: 0, y: CGFloat(min(welle, 5)) * 14)
        richtung = 1
        takt = 0
        knaeuel = []
        schuesse = []
        naechsterWurf = 1.5
    }

    private func feuern() {
        guard zeit >= naechsterSchuss, zeit > unverwundbarBis else { return }
        schuesse.append(CGPoint(x: schornsteinX, y: lokY - 30))
        naechsterSchuss = zeit + Wollalarm.schussTakt
    }

    /// Ein Prellbock aus 14 × 9 Steinchen: Balken oben, zwei Stützen darunter.
    private static func bauePrellboecke(breite: CGFloat, y: CGFloat) -> [Prellbock] {
        let form: [[Bool]] = (0..<9).map { reihe in
            (0..<14).map { spalte in
                if reihe == 0 { return spalte >= 1 && spalte <= 12 }
                if reihe <= 2 { return true }
                return (spalte >= 1 && spalte <= 4) || (spalte >= 9 && spalte <= 12)
            }
        }
        let b = 14 * zelle
        return (0..<4).map { i in
            let mitte = breite * (CGFloat(i) + 0.5) / 4
            return Prellbock(ursprung: CGPoint(x: mitte - b / 2, y: y), zellen: form)
        }
    }

    // MARK: Ein Zeitschritt

    func schritt(_ dt: Double) {
        zeit += dt
        blitze.removeAll { zeit - $0.zeit > 0.35 }
        if let b = bonus, zeit - b.zeit > 1.2 { bonus = nil }
        guard phase == .laeuft else { return }

        // Lok fährt, solange eine Pfeiltaste gedrückt ist
        if zeit > unverwundbarBis - 0.6 {
            let neu = lokX + steuer * CGFloat(360 * dt)
            let rand: CGFloat = 30
            let begrenzt = min(max(neu, rand), feld.width - rand)
            lokWeg += Double(begrenzt - lokX) / 6
            lokX = begrenzt
        }

        if dampfGehalten { feuern() }
        bewegeSchuesse(dt)

        // Formation: je weniger Katzen, desto schneller
        let lebend = katzen.filter(\.lebt).count
        let intervall = max(0.03, 0.04 + 0.55 * Double(lebend) / Double(katzen.count) - Double(min(welle, 5)) * 0.03)
        takt += dt
        while takt >= intervall {
            takt -= intervall
            formationsSchritt()
        }

        naechsterWurf -= dt
        if naechsterWurf <= 0 {
            werfen()
            naechsterWurf = .random(in: 0.5...1.3) * max(0.45, 1 - Double(welle) * 0.1)
        }
        bewegeKnaeuel(dt)
        bewegeKontrolleur(dt)

        // Katzen unten angekommen: verloren
        if katzen.contains(where: { $0.lebt && ort($0).y > lokY - 34 }) {
            beenden()
            return
        }
        if lebend == 0 {
            welle += 1
            neueWelle()
        }
    }

    private func formationsSchritt() {
        let lebende = katzen.filter(\.lebt).map(ort)
        guard let links = lebende.map(\.x).min(), let rechts = lebende.map(\.x).max() else { return }
        let rand: CGFloat = 18
        if (richtung > 0 && rechts + 6 > feld.width - rand) || (richtung < 0 && links - 6 < rand) {
            versatz.y += 14
            richtung *= -1
        } else {
            versatz.x += 6 * richtung
        }
        bild.toggle()
    }

    private func bewegeSchuesse(_ dt: Double) {
        var bleiben: [CGPoint] = []
        for var s in schuesse {
            s.y -= CGFloat(560 * dt)
            if s.y < 40 { continue }
            if treffer(s) { continue }
            bleiben.append(s)
        }
        schuesse = bleiben
    }

    /// Trifft eine Wolke etwas? Katze, Kontrolleur oder Prellbock.
    private func treffer(_ s: CGPoint) -> Bool {
        for i in katzen.indices where katzen[i].lebt {
            let k = ort(katzen[i])
            if abs(s.x - k.x) < 13, abs(s.y - k.y) < 12 {
                katzen[i].lebt = false
                gewinnen(Wollalarm.wert(reihe: katzen[i].reihe))
                blitze.append(Blitz(ort: k, zeit: zeit, gross: false))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return true
            }
        }
        if let k = kontrolleur, abs(s.x - k.x) < 18, abs(s.y - k.y) < 14 {
            let extra = [50, 100, 150, 300].randomElement()!
            gewinnen(extra)
            bonus = ("+\(extra)", k, zeit)
            blitze.append(Blitz(ort: k, zeit: zeit, gross: true))
            kontrolleur = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return true
        }
        return trifftPrellbock(s)
    }

    private func werfen() {
        let spalten = Set(katzen.filter(\.lebt).map(\.spalte))
        guard let spalte = spalten.randomElement(),
              let unterste = katzen.filter({ $0.lebt && $0.spalte == spalte }).max(by: { $0.reihe < $1.reihe })
        else { return }
        let o = ort(unterste)
        knaeuel.append(CGPoint(x: o.x, y: o.y + 12))
    }

    private func bewegeKnaeuel(_ dt: Double) {
        var bleiben: [CGPoint] = []
        for var k in knaeuel {
            k.y += CGFloat((190 + Double(min(welle, 5)) * 15) * dt)
            if k.y > feld.height { continue }
            if trifftPrellbock(k) { continue }
            if zeit > unverwundbarBis, abs(k.x - lokX) < 24, k.y > lokY - 28, k.y < lokY + 6 {
                getroffen()
                continue
            }
            bleiben.append(k)
        }
        knaeuel = bleiben
    }

    private func getroffen() {
        leben -= 1
        blitze.append(Blitz(ort: CGPoint(x: lokX, y: lokY - 14), zeit: zeit, gross: true))
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        unverwundbarBis = zeit + 1.6
        knaeuel = []
        if leben <= 0 { beenden() }
    }

    private func bewegeKontrolleur(_ dt: Double) {
        if var k = kontrolleur {
            k.x += kontrolleurRichtung * CGFloat(85 * dt)
            kontrolleur = (k.x < -30 || k.x > feld.width + 30) ? nil : k
            return
        }
        naechsterKontrolleur -= dt
        if naechsterKontrolleur <= 0 {
            kontrolleurRichtung = Bool.random() ? 1 : -1
            kontrolleur = CGPoint(x: kontrolleurRichtung > 0 ? -25 : feld.width + 25, y: 70)
            naechsterKontrolleur = .random(in: 18...30)
        }
    }

    /// Trifft der Punkt ein Steinchen? Dann bröckeln es und ein, zwei Nachbarn weg.
    private func trifftPrellbock(_ p: CGPoint) -> Bool {
        for i in prellboecke.indices {
            let o = prellboecke[i].ursprung
            let spalte = Int((p.x - o.x) / Wollalarm.zelle), reihe = Int((p.y - o.y) / Wollalarm.zelle)
            guard p.x >= o.x, p.y >= o.y, reihe < 9, spalte < 14, prellboecke[i].zellen[reihe][spalte] else { continue }
            prellboecke[i].zellen[reihe][spalte] = false
            for _ in 0..<3 {
                let r = reihe + Int.random(in: -1...1), s = spalte + Int.random(in: -1...1)
                if (0..<9).contains(r), (0..<14).contains(s) { prellboecke[i].zellen[r][s] = false }
            }
            return true
        }
        return false
    }

    private func gewinnen(_ n: Int) {
        punkte += n
        if punkte > rekord {
            rekord = punkte
            UserDefaults.standard.set(rekord, forKey: "wollalarm.rekord")
        }
    }

    private func beenden() {
        phase = .ende
        knaeuel = []
        schuesse = []
        dampfGehalten = false
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - Ansicht

struct WollalarmSpiel: View {
    @State private var spiel = Wollalarm()
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, _ in zeichnen(ctx) }
                    .contentShape(Rectangle())
                    .onTapGesture { spiel.starten() }
                anzeige
                tafel
                tasten
            }
            .onAppear { spiel.feld = geo.size }
            .onChange(of: geo.size) { _, neu in spiel.feld = neu }
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .topTrailing) {
            Button { schliessen() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .padding(.trailing, 16)
            .padding(.top, 4)
        }
        .statusBarHidden()
        // Berührungen am Bildschirmrand sofort ans Spiel geben, nicht erst auf Systemgesten warten
        .defersSystemGestures(on: .all)
        .persistentSystemOverlays(.hidden)
        .task {
            var vorher = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let jetzt = Date.now
                spiel.schritt(min(0.05, jetzt.timeIntervalSince(vorher)))
                vorher = jetzt
            }
        }
    }

    /// Unten: die Wippe zum Fahren, rechts die Dampftaste.
    private var tasten: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                Wippe { spiel.steuer = $0 }
                Spacer(minLength: 10)
                Dampftaste { spiel.dampf(gedrueckt: $0) }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
    }

    /// Punkte und Rekord oben.
    private var anzeige: some View {
        VStack {
            HStack {
                Text(String(format: "%05d", spiel.punkte))
                Spacer()
                Text("Rekord " + String(format: "%05d", spiel.rekord))
                    .foregroundStyle(.secondary)
                Spacer().frame(width: 56)
            }
            .font(.system(.headline, design: .monospaced))
            .padding(.horizontal, 20)
            .padding(.top, 14)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    /// Start- und Endtafel.
    @ViewBuilder private var tafel: some View {
        switch spiel.phase {
        case .start:
            VStack(spacing: 14) {
                Text("Wollalarm")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                Text("Wippe: fahren · Dampf: pusten")
                    .foregroundStyle(.secondary)
                Text("Tippen zum Start")
                    .font(.headline)
                    .padding(.top, 20)
            }
            .allowsHitTesting(false)
        case .ende:
            VStack(spacing: 12) {
                Text("Ende")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                Text("\(spiel.punkte) Punkte")
                    .font(.title3.monospacedDigit())
                if spiel.punkte > 0 && spiel.punkte == spiel.rekord {
                    Text("Neuer Rekord!").font(.headline)
                }
                Text("Tippen für ein neues Spiel")
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
            }
            .padding(24)
            .background(Color(.systemBackground).opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .allowsHitTesting(false)
        case .laeuft:
            EmptyView()
        }
    }

    // MARK: Zeichnen

    private let strich = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)

    private func zeichnen(_ ctx: GraphicsContext) {
        let s = spiel
        // Boden
        var boden = Path()
        boden.move(to: CGPoint(x: 0, y: s.lokY + 6)); boden.addLine(to: CGPoint(x: s.feld.width, y: s.lokY + 6))
        ctx.stroke(boden, with: .foreground, style: StrokeStyle(lineWidth: 1.2))

        // Prellböcke
        for p in s.prellboecke {
            var steine = Path()
            for (r, reihe) in p.zellen.enumerated() {
                for (c, da) in reihe.enumerated() where da {
                    steine.addRect(CGRect(x: p.ursprung.x + CGFloat(c) * Wollalarm.zelle,
                                          y: p.ursprung.y + CGFloat(r) * Wollalarm.zelle,
                                          width: Wollalarm.zelle, height: Wollalarm.zelle))
                }
            }
            ctx.fill(steine, with: .foreground)
        }

        // Katzen
        for k in s.katzen where k.lebt {
            katze(ctx, bei: s.ort(k), reihe: k.reihe, bild: s.bild)
        }

        // Kontrolleur
        if let k = s.kontrolleur { kontrolleur(ctx, bei: k) }

        // Lok (blinkt nach einem Treffer)
        let blinkt = s.zeit < s.unverwundbarBis && Int(s.zeit * 10) % 2 == 0
        if s.phase != .start, !blinkt {
            var c = ctx
            c.translateBy(x: s.lokX, y: s.lokY)
            c.scaleBy(x: 0.7, y: 0.7)
            c.translateBy(x: -37, y: -54)
            Lok.koerper(c, winkel: s.lokWeg)
        }

        // Leben oben links unter den Punkten
        for i in 0..<max(0, s.leben - 1) {
            var c = ctx
            c.translateBy(x: 34 + CGFloat(i) * 34, y: 62)
            c.scaleBy(x: 0.38, y: 0.38)
            c.translateBy(x: -37, y: -54)
            Lok.koerper(c, winkel: 0)
        }

        // Dampfwolke
        for d in s.schuesse {
            var w = Path()
            w.addEllipse(in: CGRect(x: d.x - 4, y: d.y - 5, width: 8, height: 8))
            w.addEllipse(in: CGRect(x: d.x - 6, y: d.y - 1, width: 6, height: 6))
            w.addEllipse(in: CGRect(x: d.x + 1, y: d.y, width: 5, height: 5))
            ctx.stroke(w, with: .foreground, style: StrokeStyle(lineWidth: 1.4))
        }

        // Wollknäuel
        for k in s.knaeuel {
            var w = Path()
            w.addEllipse(in: CGRect(x: k.x - 4.5, y: k.y - 4.5, width: 9, height: 9))
            let dreh = Double(k.y) / 6
            w.move(to: CGPoint(x: k.x + CGFloat(cos(dreh)) * 4, y: k.y + CGFloat(sin(dreh)) * 4))
            w.addQuadCurve(to: CGPoint(x: k.x - CGFloat(cos(dreh)) * 4, y: k.y - CGFloat(sin(dreh)) * 4),
                           control: CGPoint(x: k.x + CGFloat(sin(dreh)) * 3, y: k.y - CGFloat(cos(dreh)) * 3))
            // Losgelöster Faden
            w.move(to: CGPoint(x: k.x, y: k.y - 4.5))
            w.addQuadCurve(to: CGPoint(x: k.x + 3, y: k.y - 12), control: CGPoint(x: k.x - 4, y: k.y - 9))
            ctx.stroke(w, with: .foreground, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }

        // Treffer
        for b in s.blitze {
            let f = (s.zeit - b.zeit) / 0.35
            let r = CGFloat(4 + f * (b.gross ? 22 : 12))
            var stern = Path()
            for i in 0..<8 {
                let w = Double(i) * .pi / 4
                stern.move(to: CGPoint(x: b.ort.x + CGFloat(cos(w)) * r * 0.4, y: b.ort.y + CGFloat(sin(w)) * r * 0.4))
                stern.addLine(to: CGPoint(x: b.ort.x + CGFloat(cos(w)) * r, y: b.ort.y + CGFloat(sin(w)) * r))
            }
            var c = ctx
            c.opacity = 1 - f
            c.stroke(stern, with: .foreground, style: strich)
        }

        if let b = s.bonus {
            ctx.draw(Text(b.text).font(.system(.headline, design: .monospaced)), at: b.ort)
        }
    }

    /// Kleine struppige Katze von vorn, zwei Bilder im Wechsel (Ohren und Maul).
    private func katze(_ ctx: GraphicsContext, bei p: CGPoint, reihe: Int, bild: Bool) {
        let g: CGFloat = reihe == 0 ? 8.5 : (reihe < 3 ? 9.5 : 10.5)
        var kopf = Path()
        let n = 14
        for i in 0..<n {
            let w = Double(i) / Double(n) * 2 * .pi
            let rr = i % 2 == 0 ? g : g * 0.82
            let q = CGPoint(x: p.x + CGFloat(cos(w)) * rr, y: p.y + CGFloat(sin(w)) * rr)
            if i == 0 { kopf.move(to: q) } else { kopf.addLine(to: q) }
        }
        kopf.closeSubpath()
        // Ohren, im Wechsel gekippt
        let kipp: CGFloat = bild ? 2 : -2
        var ohren = Path()
        for s in [CGFloat(-1), CGFloat(1)] {
            ohren.move(to: CGPoint(x: p.x + s * g * 0.35, y: p.y - g * 0.75))
            ohren.addLine(to: CGPoint(x: p.x + s * g * 0.95 + kipp, y: p.y - g * 1.45))
            ohren.addLine(to: CGPoint(x: p.x + s * g * 0.9, y: p.y - g * 0.4))
        }
        ctx.stroke(ohren, with: .foreground, style: strich)
        ctx.stroke(kopf, with: .foreground, style: strich)
        // Große Augen
        var augen = Path()
        for s in [CGFloat(-1), CGFloat(1)] {
            augen.addEllipse(in: CGRect(x: p.x + s * g * 0.38 - g * 0.3, y: p.y - g * 0.35, width: g * 0.6, height: g * 0.65))
        }
        ctx.stroke(augen, with: .foreground, style: StrokeStyle(lineWidth: 1.3))
        var pupillen = Path()
        for s in [CGFloat(-1), CGFloat(1)] {
            pupillen.addEllipse(in: CGRect(x: p.x + s * g * 0.38 - 1.3, y: p.y - g * 0.05, width: 2.6, height: 2.6))
        }
        ctx.fill(pupillen, with: .foreground)
        // Maul auf, Maul zu
        var maul = Path()
        if bild {
            maul.addEllipse(in: CGRect(x: p.x - 2, y: p.y + g * 0.4, width: 4, height: 3.5))
        } else {
            maul.move(to: CGPoint(x: p.x - 2.5, y: p.y + g * 0.5)); maul.addLine(to: CGPoint(x: p.x + 2.5, y: p.y + g * 0.5))
        }
        ctx.stroke(maul, with: .foreground, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    /// Kopf eines Kontrolleurs mit Mütze und Schnauzbart.
    private func kontrolleur(_ ctx: GraphicsContext, bei p: CGPoint) {
        var k = Path()
        k.addEllipse(in: CGRect(x: p.x - 10, y: p.y - 8, width: 20, height: 20))
        // Mütze mit Schirm
        k.addRoundedRect(in: CGRect(x: p.x - 11, y: p.y - 16, width: 22, height: 9), cornerSize: CGSize(width: 3, height: 3))
        k.move(to: CGPoint(x: p.x - 14, y: p.y - 7)); k.addLine(to: CGPoint(x: p.x + 14, y: p.y - 7))
        // Augen und Schnauzbart
        k.addEllipse(in: CGRect(x: p.x - 5, y: p.y - 2, width: 2.5, height: 2.5))
        k.addEllipse(in: CGRect(x: p.x + 2.5, y: p.y - 2, width: 2.5, height: 2.5))
        k.move(to: CGPoint(x: p.x - 7, y: p.y + 6))
        k.addQuadCurve(to: CGPoint(x: p.x, y: p.y + 4), control: CGPoint(x: p.x - 4, y: p.y + 2))
        k.addQuadCurve(to: CGPoint(x: p.x + 7, y: p.y + 6), control: CGPoint(x: p.x + 4, y: p.y + 2))
        ctx.stroke(k, with: .foreground, style: strich)
    }
}

#Preview { WollalarmSpiel() }

/// Wippe zum Fahren: Je weiter außen der Finger, desto schneller; in der Mitte steht die Lok.
/// Man kann darüber gleiten, ohne loszulassen. Sie neigt sich zur gedrückten Seite.
private struct Wippe: View {
    var steuer: (CGFloat) -> Void
    @State private var wert: CGFloat = 0
    private let breite: CGFloat = 220, hoehe: CGFloat = 72

    var body: some View {
        HStack {
            Image(systemName: "arrowtriangle.left.fill")
                .opacity(wert < 0 ? 1 : 0.45)
            Spacer()
            Capsule().frame(width: 6, height: 6).opacity(0.3)
            Spacer()
            Image(systemName: "arrowtriangle.right.fill")
                .opacity(wert > 0 ? 1 : 0.45)
        }
        .font(.title2)
        .padding(.horizontal, 24)
        .frame(width: breite, height: hoehe)
        .glassEffect(.regular, in: Capsule())
        // Neigung wie bei einer echten Wippe
        .rotation3DEffect(.degrees(Double(wert) * 14), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { w in
                    let mitte = breite / 2
                    var anteil = (w.location.x - mitte) / (mitte - 18)
                    anteil = max(-1, min(1, anteil))
                    // Kleiner ruhiger Bereich in der Mitte, außen spürbar schneller
                    let betrag = max(0, (abs(anteil) - 0.12) / 0.88)
                    let neu = (anteil < 0 ? -1 : 1) * pow(betrag, 1.3)
                    wert = neu
                    steuer(neu)
                }
                .onEnded { _ in
                    wert = 0
                    steuer(0)
                }
        )
        .animation(.interactiveSpring(response: 0.12), value: wert)
    }
}

/// Dampftaste: schießt beim Herunterdrücken; gehalten pustet sie fortlaufend.
private struct Dampftaste: View {
    var gedrueckt: (Bool) -> Void
    @State private var unten = false

    var body: some View {
        Image(systemName: "smoke.fill")
            .font(.title)
            .frame(width: 80, height: 80)
            .glassEffect(.regular, in: Circle())
            .contentShape(Circle())
            .scaleEffect(unten ? 0.88 : 1)
            .animation(.interactiveSpring(response: 0.1), value: unten)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !unten { unten = true; gedrueckt(true) }
                    }
                    .onEnded { _ in unten = false; gedrueckt(false) }
            )
    }
}
