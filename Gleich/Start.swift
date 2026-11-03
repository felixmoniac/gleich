import SwiftUI

struct Start: View {
    @State private var umgebung = Umgebung()
    @State private var merkliste = Merkliste()
    @State private var pfad: [Fahrtwunsch] = []
    /// Offene Suche und wofür; nil heißt keine Suche.
    @State private var suche: Suchauftrag?
    @AppStorage("anleitungGesehen") private var anleitungGesehen = false
    /// Verstecktes Spiel: zweimal binnen einer Sekunde links über die Übersicht hinaus wischen.
    @State private var spielt = false
    @State private var letzterWisch = Date.distantPast
    @Environment(\.scenePhase) private var szene

    var body: some View {
        NavigationStack(path: $pfad) {
            inhalt
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Fahrtwunsch.self) { w in
                    VerbindungenSeite(ziel: w.ziel, ab: w.ab, standort: umgebung.standort)
                }
        }
        .environment(merkliste)
        .fullScreenCover(isPresented: $spielt) { WollalarmSpiel() }
        // Die Suche kommt als Blatt von unten – ein Wisch nach unten bringt zurück zur Startseite.
        .sheet(item: $suche) { auftrag in
            SuchSeite(standort: umgebung.standort, zweck: auftrag.zweck) { wunsch in
                suche = nil
                pfad = [wunsch]
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
            if s == .active { Task { await umgebung.allesNeu() } }
        }
    }

    @ViewBuilder private var inhalt: some View {
        if umgebung.standort.verweigert {
            OrtungFehlt()
        } else {
            seiten
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 10) {
                        Ortsleiste { ziel in
                            pfad = [Fahrtwunsch(ziel: ziel, ab: nil)]
                        } festlegen: { name in
                            suche = Suchauftrag(zweck: .merken(name))
                        }
                        .padding(.bottom, 4)
                        punkte
                        Suchknopf { suche = Suchauftrag(zweck: .fahrt) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                    .padding(.top, 24)
                    .background(alignment: .bottom) {
                        // Die Liste läuft sanft unter Punkte und Suchfeld aus.
                        LinearGradient(colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                                       startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
                            .ignoresSafeArea()
                    }
                }
        }
    }

    private var kennungen: [String] {
        ["uebersicht"] + (umgebung.jwd ? ["jwd"] : []) + umgebung.seiten.map(\.id)
    }

    @ViewBuilder private var seiten: some View {
        if umgebung.seiten.isEmpty && !umgebung.jwd {
            // Allererster Start: nur die Lok, bis die Haltestellen da sind.
            LokScroll(laedt: umgebung.laedt || umgebung.standort.erlaubnis == .notDetermined) {
                await umgebung.allesNeu()
            } inhalt: {
                if umgebung.ohneNetz {
                    Image(systemName: "icloud.slash")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .padding(.top, 80)
                }
            }
        } else {
            TabView(selection: $umgebung.seite) {
                // Unsichtbare Seite links der Übersicht: Wer hierher wischt, federt sofort zurück.
                Color(.systemBackground)
                    .tag(Optional("tor"))
                Uebersicht(plaene: umgebung.plaene, quelleVBB: umgebung.seiten.first?.halt.quelle == .vbb)
                    .tag(Optional("uebersicht"))
                if umgebung.jwd {
                    LokScroll(laedt: umgebung.laedt) { await umgebung.allesNeu() } inhalt: {
                        JWDSeite().padding(.top, 40)
                    }
                    .tag(Optional("jwd"))
                }
                ForEach(umgebung.seiten) { m in
                    HaltSeite(modell: m, umgebung: umgebung)
                        .tag(Optional(m.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: umgebung.seite) { _, neu in
                if neu == "tor" {
                    if Date.now.timeIntervalSince(letzterWisch) < 1 {
                        letzterWisch = .distantPast
                        spielt = true
                    } else {
                        letzterWisch = .now
                    }
                    withAnimation(.snappy(duration: 0.25)) { umgebung.seite = "uebersicht" }
                    return
                }
                // Beim Weiterwischen die nächste Haltestelle frisch laden.
                if let m = umgebung.seiten.first(where: { $0.id == neu }) {
                    Task { await m.laden() }
                }
            }
        }
    }

    @ViewBuilder private var punkte: some View {
        let alle = kennungen
        if alle.count > 1 {
            HStack(spacing: 7) {
                ForEach(alle, id: \.self) { k in
                    let farbe = k == umgebung.seite ? Color.primary : Color.secondary.opacity(0.35)
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
            .animation(.smooth, value: umgebung.seite)
        }
    }
}

struct Suchauftrag: Identifiable {
    let id = UUID()
    var zweck: SuchSeite.Zweck
}

/// Unter einer kurzen Linie: Zuhause, Arbeit, weitere gemerkte Orte und „+“ für einen neuen.
/// Ein Tipp sucht gleich die Verbindung dorthin; ist der Ort noch nicht festgelegt, wird er erst gesucht.
struct Ortsleiste: View {
    var fahren: (Ziel) -> Void
    /// Ort für diesen Namen suchen; nil heißt ganz neuer Ort.
    var festlegen: (String?) -> Void

    @Environment(Merkliste.self) private var merkliste

    private var weitere: [Gemerkt] {
        merkliste.orte.filter { !["zuhause", "arbeit"].contains(Gemerkt.art($0.name)) }
    }

    var body: some View {
        VStack(spacing: 14) {
            Rectangle()
                .fill(Color.primary)
                .frame(height: 1)
                .containerRelativeFrame(.horizontal, count: 5, span: 3, spacing: 0)
            ViewThatFits(in: .horizontal) {
                reihe
                ScrollView(.horizontal, showsIndicators: false) { reihe.padding(.horizontal, 2) }
                    .scrollClipDisabled()
            }
        }
    }

    private var reihe: some View {
        HStack(spacing: 10) {
            fest("Zuhause")
            fest("Arbeit")
            ForEach(weitere) { g in
                knopf(g.name, symbol: g.symbol, da: true) { fahren(g.ziel) }
                    .contextMenu {
                        Button("Anderen Ort wählen", systemImage: "mappin.and.ellipse") { festlegen(g.name) }
                        Button("Vergessen", systemImage: "trash", role: .destructive) { merkliste.vergessen(g) }
                    }
            }
            Button { festlegen(nil) } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("Neuer Ort")
        }
    }

    @ViewBuilder private func fest(_ name: String) -> some View {
        if let g = merkliste.ort(name) {
            knopf(name, symbol: g.symbol, da: true) { fahren(g.ziel) }
                .contextMenu {
                    Button("Anderen Ort wählen", systemImage: "mappin.and.ellipse") { festlegen(name) }
                    Button("Vergessen", systemImage: "trash", role: .destructive) { merkliste.vergessen(g) }
                }
        } else {
            knopf(name, symbol: Gemerkt.symbol(fuer: name), da: false) { festlegen(name) }
        }
    }

    private func knopf(_ name: String, symbol: String, da: Bool, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(name).lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(da ? Color.primary : Color.secondary)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
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
