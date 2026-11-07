import SwiftUI

/// Wohin die Startseite weiterführt.
enum Schritt: Hashable {
    /// Abfahrten einer Haltestelle (nach ihrer Kennung).
    case halt(String)
    case fahrt(Fahrtwunsch)
}

struct Start: View {
    @State private var umgebung = Umgebung()
    @State private var merkliste = Merkliste()
    @State private var pfad: [Schritt] = []
    @State private var seite: String? = "nah"
    /// Offene Suche und wofür; nil heißt keine Suche.
    @State private var suche: Suchauftrag?
    @AppStorage("anleitungGesehen") private var anleitungGesehen = false
    /// Verstecktes Spiel: zweimal binnen einer Sekunde links über die Übersicht hinaus wischen.
    @State private var spielt = false
    @State private var letzterWisch = Date.distantPast
    /// Höhe des ganzen Bildschirms – damit der Trenner genau in der Mitte sitzt.
    @State private var bildschirm: CGFloat = 0
    @Environment(\.scenePhase) private var szene

    var body: some View {
        NavigationStack(path: $pfad) {
            inhalt
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Schritt.self) { s in
                    switch s {
                    case .halt(let id):
                        if let m = umgebung.modell(id) {
                            HaltSeite(modell: m, umgebung: umgebung)
                        }
                    case .fahrt(let w):
                        VerbindungenSeite(ziel: w.ziel, ab: w.ab, standort: umgebung.standort)
                    }
                }
        }
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bildschirm = $0 }
                .ignoresSafeArea()
        }
        .environment(merkliste)
        .fullScreenCover(isPresented: $spielt) { WollalarmSpiel() }
        // Die Suche kommt als Blatt von unten – ein Wisch nach unten bringt zurück zur Startseite.
        .sheet(item: $suche) { auftrag in
            SuchSeite(standort: umgebung.standort, zweck: auftrag.zweck) { wunsch in
                suche = nil
                pfad = [.fahrt(wunsch)]
            } schliessen: {
                suche = nil
            }
            .environment(merkliste)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if !anleitungGesehen {
                AnleitungHinweis { withAnimation(.smooth) { anleitungGesehen = true } }
                    .transition(.opacity)
            }
        }
        .onChange(of: szene, initial: true) { _, s in
            switch s {
            case .active: Task { await umgebung.allesNeu() }
            case .background: umgebung.zurueckgelassen()
            default: break
            }
        }
        // Ist eine geöffnete Haltestelle nicht mehr in der Nähe, geht es zurück zur Startseite.
        .onChange(of: umgebung.seiten.map(\.id)) { _, ids in
            pfad.removeAll { if case .halt(let id) = $0 { !ids.contains(id) } else { false } }
        }
    }

    @ViewBuilder private var inhalt: some View {
        if umgebung.standort.verweigert {
            OrtungFehlt()
        } else {
            seiten
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 10) {
                        punkte
                        Suchknopf { suche = Suchauftrag(zweck: .fahrt) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                    .padding(.top, 10)
                }
        }
    }

    private var seiten: some View {
        TabView(selection: $seite) {
            // Unsichtbare Seite links der Übersicht: Wer hierher wischt, federt sofort zurück.
            Color(.systemBackground)
                .tag(Optional("tor"))
            Uebersicht(plaene: umgebung.plaene, quelleVBB: umgebung.seiten.first?.halt.quelle == .vbb)
                .tag(Optional("uebersicht"))
            nah
                .tag(Optional("nah"))
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: seite) { _, neu in
            guard neu == "tor" else { return }
            if Date.now.timeIntervalSince(letzterWisch) < 1 {
                letzterWisch = .distantPast
                spielt = true
            } else {
                letzterWisch = .now
            }
            withAnimation(.snappy(duration: 0.25)) { seite = "uebersicht" }
        }
    }

    /// Die Startseite: oben die Haltestellen in der Nähe, ab der Bildschirmmitte die eigenen Orte.
    private var nah: some View {
        GeometryReader { geo in
            let oben = geo.frame(in: .global).minY
            let mitte = bildschirm > 0 ? bildschirm / 2 - oben : geo.size.height / 2
            let obenHoehe = min(max(mitte, 120), geo.size.height - 120)
            VStack(spacing: 0) {
                Haltestellenliste(umgebung: umgebung) { pfad = [.halt($0)] }
                    .frame(height: obenHoehe)
                Ortsraster { ziel in
                    pfad = [.fahrt(Fahrtwunsch(ziel: ziel, ab: nil))]
                } festlegen: { name in
                    suche = Suchauftrag(zweck: .merken(name))
                }
                .frame(height: geo.size.height - obenHoehe, alignment: .top)
            }
        }
    }

    @ViewBuilder private var punkte: some View {
        HStack(spacing: 7) {
            ForEach(["uebersicht", "nah"], id: \.self) { k in
                let farbe = k == seite ? Color.primary : Color.secondary.opacity(0.35)
                if k == "uebersicht" {
                    // Die Übersicht bekommt ein Zeichen statt eines Punkts.
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(farbe)
                } else {
                    Circle().fill(farbe).frame(width: 7, height: 7)
                }
            }
        }
        .animation(.smooth, value: seite)
    }
}

/// Nur die Namen der nächsten Haltestellen. Ein Tipp öffnet die Abfahrten, das Männchen den Fußweg.
struct Haltestellenliste: View {
    var umgebung: Umgebung
    var oeffnen: (String) -> Void

    var body: some View {
        // Die Haltestellen stehen über der Mittellinie: die nächste zuoberst, die letzte direkt über der Linie.
        LokScroll(laedt: umgebung.laedt || umgebung.standort.erlaubnis == .notDetermined, unten: true) {
            await umgebung.allesNeu()
        } inhalt: {
            VStack(alignment: .leading, spacing: 0) {
                if umgebung.jwd && !umgebung.veraltet {
                    VStack(spacing: 6) {
                        JWDBild().frame(width: 320, height: 230).scaleEffect(0.7).frame(height: 165)
                        Text("JWD – dit tut weh")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                }
                ForEach(umgebung.sichtbar) { m in
                    zeile(m)
                }
                if umgebung.sichtbar.isEmpty && umgebung.ohneNetz && !umgebung.laedt {
                    Image(systemName: "icloud.slash")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .animation(.smooth, value: umgebung.sichtbar.map(\.id))
    }

    private func zeile(_ m: HaltModell) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Namen.kurz(m.halt.name, ort: umgebung.ort))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
            if m.ohneNetz || umgebung.ohneNetz {
                Image(systemName: "icloud.slash")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Fussknopf(halt: m.halt, minuten: umgebung.gehzeit(zu: m.halt))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { oeffnen(m.id) }
        .accessibilityAddTraits(.isButton)
    }
}

/// Das Männchen mit der Gehzeit – ein Tipp zeigt den Fußweg in Apple Karten.
struct Fussknopf: View {
    var halt: Haltestelle
    var minuten: TimeInterval

    var body: some View {
        let fuss = Int((minuten / 60).rounded())
        Button { Fussweg.zeigen(halt) } label: {
            HStack(spacing: 3) {
                Image(systemName: "figure.walk")
                if fuss > 1 { Text("\(fuss) Min") }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Fußweg")
    }
}

enum Fussweg {
    static func zeigen(_ h: Haltestelle) {
        if let url = URL(string: "maps://?daddr=\(h.breite),\(h.laenge)&dirflg=w") {
            UIApplication.shared.open(url)
        }
    }
}

struct Suchauftrag: Identifiable {
    let id = UUID()
    var zweck: SuchSeite.Zweck
}

/// Unter einer kurzen Linie: Zuhause, Arbeit, weitere gemerkte Orte und „+“ für einen neuen –
/// nebeneinander und untereinander wie die Symbole auf dem Home-Bildschirm.
/// Ein Tipp sucht gleich die Verbindung dorthin; ist der Ort noch nicht festgelegt, wird er erst gesucht.
struct Ortsraster: View {
    var fahren: (Ziel) -> Void
    /// Ort für diesen Namen suchen; nil heißt ganz neuer Ort.
    var festlegen: (String?) -> Void

    @Environment(Merkliste.self) private var merkliste

    private var weitere: [Gemerkt] {
        merkliste.orte.filter { !["zuhause", "arbeit"].contains(Gemerkt.art($0.name)) }
    }

    private let spalten = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary)
                .frame(height: 1)
                .containerRelativeFrame(.horizontal, count: 5, span: 3, spacing: 0)
            ScrollView {
                LazyVGrid(columns: spalten, spacing: 18) {
                    fest("Zuhause")
                    fest("Arbeit")
                    ForEach(weitere) { g in
                        kachel(g.name, symbol: g.symbol, da: true) { fahren(g.ziel) }
                            .contextMenu {
                                Button("Anderen Ort wählen", systemImage: "mappin.and.ellipse") { festlegen(g.name) }
                                Button("Vergessen", systemImage: "trash", role: .destructive) { merkliste.vergessen(g) }
                            }
                    }
                    kachel("Neu", symbol: "plus", da: false) { festlegen(nil) }
                        .accessibilityLabel("Neuer Ort")
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder private func fest(_ name: String) -> some View {
        if let g = merkliste.ort(name) {
            kachel(name, symbol: g.symbol, da: true) { fahren(g.ziel) }
                .contextMenu {
                    Button("Anderen Ort wählen", systemImage: "mappin.and.ellipse") { festlegen(name) }
                    Button("Vergessen", systemImage: "trash", role: .destructive) { merkliste.vergessen(g) }
                }
        } else {
            kachel(name, symbol: Gemerkt.symbol(fuer: name), da: false) { festlegen(name) }
        }
    }

    private func kachel(_ name: String, symbol: String, da: Bool, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(da ? Color.primary : Color.secondary)
                    .frame(width: 62, height: 62)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(da ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Das Suchfeld unten. Ein Tipp öffnet die Suche.
struct Suchknopf: View {
    var aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                Text("Wohin?")
                Spacer()
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 50)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

struct OrtungFehlt: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "location.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Gleich braucht deinen Standort, um zu zeigen, was in deiner Nähe abfährt.")
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.glassProminent)
        }
        .padding(32)
    }
}
