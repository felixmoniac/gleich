import SwiftUI

/// Suche nach einem Ziel. Gemerkte Orte stehen oben, das Eingabefeld unten.
struct SuchSeite: View {
    /// Wofür gesucht wird: eine Fahrt – oder ein Ort, der gemerkt werden soll (Zuhause, Arbeit oder ganz neu).
    enum Zweck: Equatable {
        case fahrt
        case merken(String?)
    }

    var standort: Standort
    var zweck: Zweck = .fahrt
    var gewaehlt: (Fahrtwunsch) -> Void
    var schliessen: () -> Void

    @Environment(Merkliste.self) private var merkliste
    @State private var text = ""
    @State private var treffer: [Ziel] = []
    @State private var sucht = false
    /// Gewählte Abfahrtszeit; nil heißt jetzt.
    @State private var ab: Date?
    @State private var waehltZeit = false
    @State private var rauch = Rauch()
    @FocusState private var fokus: Bool

    @State private var zuMerken: Ziel?
    @State private var zuBenennen: Gemerkt?
    @State private var name = ""

    private var gemerkte: [Gemerkt] {
        guard zweck == .fahrt else { return [] }
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return merkliste.orte }
        return merkliste.orte.filter { $0.name.lowercased().contains(t) || $0.ziel.name.lowercased().contains(t) }
    }

    private var suchtNoch: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    private var platzhalter: String {
        switch zweck {
        case .fahrt: "Wohin?"
        case .merken(nil): "Welcher Ort?"
        case .merken(let name?): Gemerkt.art(name) == "arbeit" ? "Wo ist die Arbeit?" : "Wo ist \(name)?"
        }
    }

    /// Ein Ziel wurde angetippt.
    private func waehlen(_ z: Ziel) {
        rauch.ruht = true
        rauch.leeren()
        switch zweck {
        case .fahrt:
            gewaehlt(Fahrtwunsch(ziel: z, ab: ab))
        case .merken(let name?):
            merkliste.festlegen(z, als: name)
            gewaehlt(Fahrtwunsch(ziel: z, ab: nil))
        case .merken(nil):
            name = z.name
            zuMerken = z
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(gemerkte) { g in
                    Button { waehlen(g.ziel) } label: {
                        ZielZeile(symbol: g.symbol, name: g.name,
                                  zusatz: g.name == g.ziel.name ? g.ziel.zusatz : g.ziel.name, betont: true)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Umbenennen", systemImage: "pencil") { name = g.name; zuBenennen = g }
                        Button("Vergessen", systemImage: "trash", role: .destructive) { merkliste.vergessen(g) }
                    }
                }
                ForEach(treffer) { z in
                    Button { waehlen(z) } label: {
                        ZielZeile(symbol: z.haltID != nil ? "tram.fill" : "mappin", name: z.name, zusatz: z.zusatz)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Merken", systemImage: "star") { name = z.name; zuMerken = z }
                    }
                }
                if suchtNoch {
                    // Solange noch nichts gesucht ist: ein kleiner Zug fährt im Kreis.
                    ZugImKreis(rauch: rauch)
                        .frame(maxWidth: .infinity)
                        .padding(.top, gemerkte.isEmpty ? 150 : 40)
                }
                if sucht && treffer.isEmpty {
                    Lok(ruckelt: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                }
            }
            .padding(.top, 20)
        }
        .coordinateSpace(.named("suche"))
        // Rauchwolken und Sprüche über der ganzen Suche – sobald etwas getippt ist, sind sie weg.
        .overlay { if suchtNoch { RauchBild(rauch: rauch).clipped() } }
        .onChange(of: suchtNoch) { _, leer in
            rauch.ruht = !leer
            if !leer { rauch.leeren() }
        }
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.top)
        .background(.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { eingabe }
        .onAppear { fokus = true }
        .task(id: text) { await suchen() }
        .alert("Merken als", isPresented: Binding(get: { zuMerken != nil }, set: { if !$0 { zuMerken = nil } })) {
            TextField("Name", text: $name)
            Button("Merken") {
                if let z = zuMerken { merkliste.merken(z, als: name) }
                if zweck != .fahrt { schliessen() }
            }
            Button("Abbrechen", role: .cancel) { }
        }
        .alert("Umbenennen", isPresented: Binding(get: { zuBenennen != nil }, set: { if !$0 { zuBenennen = nil } })) {
            TextField("Name", text: $name)
            Button("Sichern") { if let g = zuBenennen { merkliste.umbenennen(g, in: name) } }
            Button("Abbrechen", role: .cancel) { }
        }
    }

    private var eingabe: some View {
        HStack(spacing: 10) {
            if zweck == .fahrt {
                ZeitKnopf(ab: ab) { waehltZeit = true }
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(platzhalter, text: $text)
                    .focused($fokus)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit {
                        if let erster = gemerkte.first?.ziel ?? treffer.first { waehlen(erster) }
                    }
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 18)
            .frame(height: 50)
            .glassEffect(.regular, in: Capsule())

            Button(action: schliessen) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .sheet(isPresented: $waehltZeit) {
            ZeitWahl(ab: $ab)
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
    }

    private func suchen() async {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { treffer = []; return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        sucht = true
        defer { sucht = false }
        if let liste = try? await Transitous.suchen(t, nahe: standort.ort?.coordinate), !Task.isCancelled {
            treffer = Array(liste.prefix(12))
        }
    }
}

struct ZielZeile: View {
    var symbol: String
    var name: String
    var zusatz: String?
    var betont = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(betont ? Color.primary : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.body.weight(betont ? .semibold : .medium))
                    .lineLimit(1)
                if let zusatz, !zusatz.isEmpty {
                    Text(zusatz)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Abfahrtszeit: zeigt „Jetzt“ oder die gewählte Zeit, ein Tipp lässt sie ändern.
struct ZeitKnopf: View {
    var ab: Date?
    var aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                Text(ab.map(Zeit.wann) ?? "Jetzt")
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(height: 50)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

/// Abfahrtszeit wählen – oder zurück auf „Jetzt“.
struct ZeitWahl: View {
    @Binding var ab: Date?
    @State private var zeit = Date.now
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        VStack(spacing: 16) {
            DatePicker("Abfahrt", selection: $zeit, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "de_DE"))
            HStack(spacing: 12) {
                Button {
                    ab = nil
                    schliessen()
                } label: {
                    Text("Jetzt").frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.glass)
                Button {
                    ab = zeit
                    schliessen()
                } label: {
                    Text("Fertig").fontWeight(.semibold).frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .onAppear { zeit = ab ?? .now }
    }
}
