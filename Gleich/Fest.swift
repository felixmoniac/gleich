import SwiftUI

/// Die festgehaltene Verbindung oben auf der Startseite: Ziel, Ankunft und der nächste Einstieg.
/// Antippen öffnet sie ganz, lange drücken lässt sie los.
struct FestKarte: View {
    var fest: Festgehalten
    var oeffnen: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { kontext in
            let jetzt = kontext.date
            let v = fest.verbindung
            let naechste = v.fahrten.first { $0.ab > jetzt.addingTimeInterval(-30) } ?? v.fahrten.last
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Namen.kurz(fest.ziel.name))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("an " + Zeit.uhr.string(from: v.an))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(v.an.timeIntervalSince(v.anGeplant) >= 60 ? Color.red : Color.primary)
                }
                if let a = naechste {
                    HStack(spacing: 8) {
                        if let l = a.linie { LinienSymbol(linie: l, klein: true) }
                        Text(Zeit.uhr.string(from: a.ab))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(a.abVerspaetet || a.faelltAus ? Color.red : Color.primary)
                            .strikethrough(a.faelltAus)
                        Text(Namen.kurz(a.von))
                            .font(.subheadline)
                            .lineLimit(1)
                        if let g = a.gleis {
                            Text("Gl. \(g)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Text(a.faelltAus ? "fällt aus" : Zeit.bis(a.ab, ab: jetzt))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(a.faelltAus ? Color.red : Color.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22))
            .onTapGesture(perform: oeffnen)
            .contextMenu {
                Button(role: .destructive) {
                    withAnimation(.snappy) { Festhalter.geteilt.loslassen() }
                } label: {
                    Label("Loslassen", systemImage: "pin.slash")
                }
            }
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// Die festgehaltene Verbindung mit allen Schritten. Runterziehen holt die aktuellen Zeiten.
struct FestSeite: View {
    private var festhalter: Festhalter { .geteilt }
    @Environment(\.dismiss) private var zurueck

    var body: some View {
        LokScroll(laedt: festhalter.laedt) { await festhalter.auffrischen() } inhalt: {
            if let f = festhalter.fest {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Namen.kurz(f.ziel.name))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Image(systemName: "pin.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    Schritte(verbindung: f.verbindung)
                }
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { leiste }
        .onChange(of: festhalter.fest == nil) { _, weg in if weg { zurueck() } }
    }

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

            Spacer(minLength: 0)

            Button {
                withAnimation(.snappy) { festhalter.loslassen() }
            } label: {
                Label("Loslassen", systemImage: "pin.slash")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
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
}
