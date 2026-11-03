import SwiftUI

/// Verbindungen von hier zum Ziel, ab jetzt. Weiter unten kommen spätere.
struct VerbindungenSeite: View {
    var ziel: Ziel
    var standort: Standort

    @State private var liste: [Verbindung] = []
    @State private var weiter: String?
    @State private var laedt = false
    @State private var ohneNetz = false
    @State private var offen: String?
    @State private var holtMehr = false

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
                        .onAppear { if v.id == liste.last?.id { Task { await mehr() } } }
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { if liste.isEmpty { await laden() } }
    }

    private func laden() async {
        guard !laedt else { return }
        laedt = true
        defer { laedt = false }
        guard let ort = await standort.frisch() else { return }
        do {
            let e = try await Transitous.verbindungen(von: ort.coordinate, nach: ziel)
            liste = e.liste.filter { $0.an > .now }
            weiter = e.weiter
            ohneNetz = false
        } catch {
            ohneNetz = true
        }
    }

    private func mehr() async {
        guard !holtMehr, !laedt, let w = weiter, let ort = standort.ort else { return }
        holtMehr = true
        defer { holtMehr = false }
        guard let e = try? await Transitous.verbindungen(von: ort.coordinate, nach: ziel, weiter: w) else { return }
        let bekannt = Set(liste.map(\.id))
        liste += e.liste.filter { !bekannt.contains($0.id) }
        weiter = e.weiter
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
