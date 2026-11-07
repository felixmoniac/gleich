import ActivityKit
import SwiftUI
import WidgetKit

/// Die festgehaltene Verbindung auf dem Sperrbildschirm und in der Dynamic Island.
/// Der Countdown läuft von selbst; neue Verspätungen bringt die App mit, sobald sie läuft.
struct FahrtLive: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FahrtAktivitaet.self) { k in
            FahrtSperrbild(ziel: k.attributes.ziel, zustand: k.state, vorbei: k.isStale)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        } dynamicIsland: { k in
            let s = k.state
            let n = s.teile.indices.contains(s.naechste) ? s.teile[s.naechste] : nil
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let n { LinienSymbol(linie: n.linie).padding(.leading, 4) }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let n { Countdown(ab: n.ab, ausfall: n.faelltAus).font(.title3.weight(.semibold)).padding(.trailing, 4) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FahrtSperrbild(ziel: k.attributes.ziel, zustand: s, vorbei: k.isStale, ohneZaehler: true)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                if let n { LinienSymbol(linie: n.linie, klein: true) }
            } compactTrailing: {
                if let n {
                    Countdown(ab: n.ab, ausfall: n.faelltAus)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: 44)
                }
            } minimal: {
                if let n { LinienSymbol(linie: n.linie, klein: true) }
            }
        }
    }
}

/// Zählt bis zur Abfahrt herunter und bleibt dann bei 0:00 stehen.
private struct Countdown: View {
    var ab: Date
    var ausfall: Bool

    var body: some View {
        if ausfall {
            Text("fällt aus").foregroundStyle(.red)
        } else {
            let jetzt = Date.now
            Text(timerInterval: jetzt...max(jetzt, ab), countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct FahrtSperrbild: View {
    var ziel: String
    var zustand: FahrtAktivitaet.ContentState
    var vorbei: Bool
    var ohneZaehler = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ziel)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("an " + Zeit.uhr.string(from: zustand.an))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(zustand.anVerspaetet ? Color.red : Color.primary)
            }
            // Was schon gefahren ist, fällt weg; höchstens drei Fahrten.
            let rest = Array(zustand.teile.enumerated()).dropFirst(zustand.naechste).prefix(3)
            ForEach(Array(rest), id: \.offset) { i, t in
                HStack(spacing: 8) {
                    LinienSymbol(linie: t.linie, klein: true)
                    Text(Zeit.uhr.string(from: t.ab))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(t.abVerspaetet || t.faelltAus ? Color.red : Color.primary)
                        .strikethrough(t.faelltAus)
                    Text(t.von)
                        .font(.subheadline)
                        .lineLimit(1)
                    if let g = t.gleis {
                        Text("Gl. \(g)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    if i == zustand.naechste && !ohneZaehler {
                        Countdown(ab: t.ab, ausfall: t.faelltAus)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: 70, alignment: .trailing)
                    }
                }
            }
        }
        .opacity(vorbei ? 0.45 : 1)
    }
}
