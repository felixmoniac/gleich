import SwiftUI

struct Start: View {
    @State private var umgebung = Umgebung()
    @State private var merkliste = Merkliste()
    @State private var pfad: [Ziel] = []
    @State private var suchtGerade = false
    @AppStorage("anleitungGesehen") private var anleitungGesehen = false
    @Environment(\.scenePhase) private var szene

    var body: some View {
        NavigationStack(path: $pfad) {
            inhalt
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Ziel.self) { ziel in
                    VerbindungenSeite(ziel: ziel, standort: umgebung.standort)
                }
        }
        .environment(merkliste)
        .overlay {
            if suchtGerade {
                SuchSeite(standort: umgebung.standort) { ziel in
                    suchtGerade = false
                    pfad = [ziel]
                } schliessen: {
                    suchtGerade = false
                }
                .environment(merkliste)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .overlay {
            if !anleitungGesehen {
                AnleitungHinweis { withAnimation(.smooth) { anleitungGesehen = true } }
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: suchtGerade)
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
                        punkte
                        Suchknopf { suchtGerade = true }
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
