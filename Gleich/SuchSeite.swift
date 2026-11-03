import SwiftUI

/// Suche nach einem Ziel. Gemerkte Orte stehen oben, das Eingabefeld unten.
struct SuchSeite: View {
    var standort: Standort
    var gewaehlt: (Ziel) -> Void
    var schliessen: () -> Void

    @Environment(Merkliste.self) private var merkliste
    @State private var text = ""
    @State private var treffer: [Ziel] = []
    @State private var sucht = false
    @FocusState private var fokus: Bool

    @State private var zuMerken: Ziel?
    @State private var zuBenennen: Gemerkt?
    @State private var name = ""

    private var gemerkte: [Gemerkt] {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return merkliste.orte }
        return merkliste.orte.filter { $0.name.lowercased().contains(t) || $0.ziel.name.lowercased().contains(t) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(gemerkte) { g in
                    Button { gewaehlt(g.ziel) } label: {
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
                    Button { gewaehlt(z) } label: {
                        ZielZeile(symbol: z.haltID != nil ? "tram.fill" : "mappin", name: z.name, zusatz: z.zusatz)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Merken", systemImage: "star") { name = z.name; zuMerken = z }
                    }
                }
                if sucht && treffer.isEmpty {
                    Lok(ruckelt: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                }
            }
            .padding(.top, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.top)
        .background(.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { eingabe }
        .onAppear { fokus = true }
        .task(id: text) { await suchen() }
        .alert("Merken als", isPresented: Binding(get: { zuMerken != nil }, set: { if !$0 { zuMerken = nil } })) {
            TextField("Name", text: $name)
            Button("Merken") { if let z = zuMerken { merkliste.merken(z, als: name) } }
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
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Wohin?", text: $text)
                    .focused($fokus)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { if let erster = gemerkte.first?.ziel ?? treffer.first { gewaehlt(erster) } }
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
