import SwiftUI

/// Weiterer Weg einer Abfahrt: die nächsten Halte mit Uhrzeit.
struct FahrtSeite: View {
    var abfahrt: Abfahrt
    var ort: String?
    @State private var halte: [Zwischenhalt] = []
    @State private var laedt = true
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                LinienSymbol(linie: abfahrt.linie)
                Text(Namen.kurz(abfahrt.richtung, ort: ort))
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button { schliessen() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Schließen")
            }
            .padding(.leading, 24)
            .padding(.trailing, 16)
            .padding(.top, 28)
            .padding(.bottom, 12)

            if laedt && halte.isEmpty {
                Lok(ruckelt: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                Spacer()
            } else if halte.isEmpty {
                Image(systemName: "icloud.slash")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(halte) { h in
                            HaltZeile(halt: h, ort: ort, erster: h.id == halte.first?.id)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .task {
            halte = (try? await Fahrplan.verlauf(abfahrt)) ?? []
            laedt = false
        }
    }
}

struct HaltZeile: View {
    var halt: Zwischenhalt
    var ort: String?
    var erster = false
    var klein = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(halt.zeit.map(Zeit.uhr.string(from:)) ?? "")
                .monospacedDigit()
                .foregroundStyle(halt.verspaetet ? Color.red : (klein ? Color.secondary : Color.primary))
                .frame(width: 48, alignment: .trailing)
            Text(Namen.kurz(halt.name, ort: ort))
                .fontWeight(erster ? .semibold : .regular)
                .foregroundStyle(klein ? .secondary : .primary)
                .lineLimit(1)
                .strikethrough(halt.faelltAus)
            Spacer(minLength: 0)
        }
        .font(klein ? .subheadline : .body)
        .padding(.horizontal, 24)
        .padding(.vertical, klein ? 3 : 6)
    }
}
