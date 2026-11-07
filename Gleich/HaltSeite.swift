import SwiftUI

/// Eine Haltestelle: Name, bei Bedarf Symbolreihe, darunter die Abfahrten.
/// Tipp auf den Namen oder aufs Männchen zeigt den Fußweg.
struct HaltSeite: View {
    var modell: HaltModell
    var umgebung: Umgebung
    @Environment(\.dismiss) private var zurueck
    @Environment(Merkliste.self) private var merkliste
    @State private var gewaehlt: Abfahrt?
    @State private var merkName = ""
    @State private var merktGerade = false

    private var ort: String? { umgebung.ort }

    var body: some View {
        LokScroll(laedt: modell.laedt || umgebung.laedt) {
            await modell.laden()
        } inhalt: {
            VStack(alignment: .leading, spacing: 0) {
                kopf
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                if modell.mittel.count > 1 {
                    symbolreihe
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }
                TimelineView(.periodic(from: .now, by: 10)) { zeit in
                    zeilen(jetzt: zeit.date)
                }
                .padding(.top, 14)
            }
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button { zurueck() } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 50, height: 50)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Zurück")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
            .padding(.top, 20)
            .background(alignment: .bottom) {
                // Die Liste läuft sanft unter dem Knopf aus.
                LinearGradient(colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
                    .ignoresSafeArea()
            }
        }
        .task {
            if modell.abfahrten.isEmpty || modell.ohneNetz { await modell.laden() }
        }
        .sheet(item: $gewaehlt) { a in
            FahrtSeite(abfahrt: a, ort: ort)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Merken als", isPresented: $merktGerade) {
            TextField("Name", text: $merkName)
            Button("Merken") { merkliste.merken(ziel, als: merkName) }
            Button("Abbrechen", role: .cancel) { }
        }
    }

    private var ziel: Ziel {
        let h = modell.halt
        return Ziel(id: h.id, name: h.name, zusatz: nil, breite: h.breite, laenge: h.laenge,
                    haltID: h.quelle == .transitous ? h.id : nil)
    }

    private var kopf: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                Fussweg.zeigen(modell.halt)
            } label: {
                Text(Namen.kurz(modell.halt.name, ort: ort))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Fußweg", systemImage: "figure.walk") { Fussweg.zeigen(modell.halt) }
                Button("Merken", systemImage: "star") {
                    merkName = Namen.kurz(modell.halt.name)
                    merktGerade = true
                }
                Section("Daten: Transitous\(modell.halt.quelle == .vbb ? " · VBB" : "")") { }
            }
            Fussknopf(halt: modell.halt, minuten: umgebung.gehzeit(zu: modell.halt))
            if modell.ohneNetz || umgebung.ohneNetz {
                Image(systemName: "icloud.slash")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var symbolreihe: some View {
        HStack(spacing: 8) {
            ForEach(modell.mittel, id: \.self) { m in
                Button {
                    withAnimation(.snappy) { modell.filter = modell.filter == m ? nil : m }
                } label: {
                    MittelSymbol(mittel: m)
                        .opacity(modell.filter == nil || modell.filter == m ? 1 : 0.3)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: modell.filter)
            }
        }
    }

    @ViewBuilder private func zeilen(jetzt: Date) -> some View {
        let liste = modell.sichtbar(jetzt: jetzt) { umgebung.erreichbar($0, an: modell.halt, jetzt: jetzt) }
        if liste.isEmpty && !modell.laedt && !umgebung.laedt {
            Text(modell.ohneNetz ? "" : "Hier fährt so bald nichts.")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
        LazyVStack(spacing: 0) {
            ForEach(liste) { a in
                Button { gewaehlt = a } label: {
                    AbfahrtZeile(abfahrt: a, ort: ort, jetzt: jetzt,
                                 erreichbar: umgebung.erreichbar(a, an: modell.halt, jetzt: jetzt))
                }
                .buttonStyle(.plain)
                .opacity(modell.ohneNetz ? 0.35 : 1)
            }
        }
    }

}

struct AbfahrtZeile: View {
    var abfahrt: Abfahrt
    var ort: String?
    var jetzt: Date
    var erreichbar: Bool

    var body: some View {
        HStack(spacing: 12) {
            LinienSymbol(linie: abfahrt.linie)
            Text(Namen.kurz(abfahrt.richtung, ort: ort))
                .font(.body.weight(.medium))
                .lineLimit(1)
                .strikethrough(abfahrt.faelltAus)
            Spacer(minLength: 6)
            if let g = abfahrt.gleis {
                Text("Gl. \(g)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(Zeit.bis(abfahrt.zeit, ab: jetzt))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .strikethrough(abfahrt.faelltAus)
                .foregroundStyle(abfahrt.verspaetet ? Color.red : Color.primary)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .opacity(abfahrt.faelltAus ? 0.45 : (erreichbar ? 1 : 0.35))
    }
}
