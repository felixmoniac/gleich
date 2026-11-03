import SwiftUI

/// Die nächsten Verbindungen von hier zum Ziel – ab jetzt oder ab der gewählten Zeit.
struct VerbindungenSeite: View {
    var ziel: Ziel
    var standort: Standort

    /// Gewählte Abfahrtszeit; nil heißt jetzt. Lässt sich unten ändern.
    @State private var ab: Date?
    @State private var waehltZeit = false
    @State private var liste: [Verbindung] = []
    @State private var laedt = false
    @State private var ohneNetz = false
    @State private var offen: String?
    /// Nur der neueste Ladevorgang trägt ein – falls die Zeit schnell hintereinander geändert wird.
    @State private var lauf = 0
    @Environment(\.dismiss) private var zurueck

    init(ziel: Ziel, ab: Date?, standort: Standort) {
        self.ziel = ziel
        self.standort = standort
        _ab = State(initialValue: ab)
    }

    var body: some View {
        LokScroll(laedt: laedt) { await laden() } inhalt: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Namen.kurz(ziel.name))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    if ohneNetz {
                        Image(systemName: "icloud.slash").font(.title3).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)

                LazyVStack(spacing: 0) {
                    ForEach(liste) { v in
                        VerbindungZeile(verbindung: v, offen: offen == v.id) {
                            withAnimation(.snappy) { offen = offen == v.id ? nil : v.id }
                        }
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { leiste }
        .sheet(isPresented: $waehltZeit) {
            ZeitWahl(ab: $ab)
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
        .task(id: ab) {
            offen = nil
            await laden()
        }
    }

    /// Unten: zurück, Abfahrtszeit ändern, spätere Verbindungen.
    private var leiste: some View {
        HStack(spacing: 10) {
            Button { zurueck() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 50, height: 50)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("Zurück")

            ZeitKnopf(ab: ab) { waehltZeit = true }

            Spacer(minLength: 0)

            Button {
                // Ab eine Minute nach der letzten gezeigten Abfahrt weitersuchen
                if let letzte = liste.last?.ab { ab = letzte.addingTimeInterval(60) }
            } label: {
                HStack(spacing: 5) {
                    Text("Später")
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(height: 50)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .disabled(liste.isEmpty)
            .opacity(liste.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .padding(.top, 20)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
                .ignoresSafeArea()
        }
    }

    private func laden() async {
        lauf += 1
        let meiner = lauf
        laedt = true
        defer { if lauf == meiner { laedt = false } }
        guard let ort = await standort.frisch() else { return }
        do {
            let e = try await Transitous.verbindungen(von: ort.coordinate, nach: ziel, ab: ab)
            guard lauf == meiner else { return }
            liste = Array(e.liste.filter { $0.an > .now }.prefix(6))
            ohneNetz = false
        } catch {
            if lauf == meiner { ohneNetz = true }
        }
    }
}

struct VerbindungZeile: View {
    var verbindung: Verbindung
    var offen: Bool
    var tippen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: tippen) {
                kurz
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if offen {
                Schritte(verbindung: verbindung)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
    }

    private var kurz: some View {
        let v = verbindung
        let zeiten = HStack(spacing: 6) {
            Text(Zeit.uhr.string(from: v.ab))
                .foregroundStyle(v.ab.timeIntervalSince(v.abGeplant) >= 60 ? Color.red : Color.primary)
            Text("→").foregroundStyle(.secondary)
            Text(Zeit.uhr.string(from: v.an))
                .foregroundStyle(v.an.timeIntervalSince(v.anGeplant) >= 60 ? Color.red : Color.primary)
        }
        .font(.title3.weight(.semibold))
        .monospacedDigit()

        let linien = HStack(spacing: 4) {
            ForEach(Array(v.fahrten.enumerated()), id: \.offset) { i, a in
                if i > 0 {
                    Text("›").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                }
                if let l = a.linie { LinienSymbol(linie: l, klein: true) }
            }
            if v.fahrten.isEmpty {
                Image(systemName: "figure.walk").foregroundStyle(.secondary)
            }
        }

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                zeiten
                linien
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                zeiten
                linien
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Aufgeklappte Verbindung: wo einsteigen, welche Linie, wo umsteigen, Fußwege.
struct Schritte: View {
    var verbindung: Verbindung
    @State private var halteOffen: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(verbindung.abschnitte) { a in
                if a.istFussweg {
                    let min = max(1, Int((a.an.timeIntervalSince(a.ab) / 60).rounded()))
                    HStack(spacing: 14) {
                        Image(systemName: "figure.walk")
                            .frame(width: 48, alignment: .trailing)
                        Text("\(min) Min")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                } else {
                    fahrt(a)
                }
            }
        }
    }

    @ViewBuilder private func fahrt(_ a: Abschnitt) -> some View {
        zeile(zeit: a.ab, rot: a.abVerspaetet, name: a.von, gleis: a.gleis)
        Button {
            withAnimation(.snappy) {
                if halteOffen.contains(a.id) { halteOffen.remove(a.id) } else { halteOffen.insert(a.id) }
            }
        } label: {
            HStack(spacing: 14) {
                Color.clear.frame(width: 48, height: 1)
                if let l = a.linie { LinienSymbol(linie: l, klein: true) }
                Text(Namen.kurz(a.richtung))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !a.zwischenhalte.isEmpty {
                    Image(systemName: halteOffen.contains(a.id) ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if halteOffen.contains(a.id) {
            ForEach(a.zwischenhalte) { h in
                HaltZeile(halt: h, klein: true)
            }
        }
        zeile(zeit: a.an, rot: a.anVerspaetet, name: a.nach, gleis: nil)
    }

    private func zeile(zeit: Date, rot: Bool, name: String, gleis: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(Zeit.uhr.string(from: zeit))
                .monospacedDigit()
                .foregroundStyle(rot ? Color.red : Color.primary)
                .frame(width: 48, alignment: .trailing)
            Text(Namen.kurz(name))
                .fontWeight(.semibold)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let gleis {
                Text("Gl. \(gleis)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }
}
