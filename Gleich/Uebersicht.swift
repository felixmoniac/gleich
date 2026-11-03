import SwiftUI
import PDFKit

/// Links von der Startseite: App, Verbund, Netzpläne, Anleitung.
struct Uebersicht: View {
    var plaene: Planablage
    var quelleVBB: Bool
    @State private var offen: Netzplan?

    /// Verbundname; ein Tipp öffnet die Auswahl. Ortspfeil = automatisch, Stecknadel = von Hand gewählt.
    private var verbundWahl: some View {
        Menu {
            Button {
                Task { await plaene.waehlen(nil) }
            } label: {
                Label("Automatisch" + (plaene.automatisch.map { " (\($0.kuerzel))" } ?? ""),
                      systemImage: plaene.wahl == nil ? "checkmark" : "location")
            }
            Divider()
            ForEach(Verbund.alle.sorted { $0.name < $1.name }, id: \.kuerzel) { v in
                Button {
                    Task { await plaene.waehlen(v.kuerzel) }
                } label: {
                    if plaene.wahl == v.kuerzel {
                        Label(v.name, systemImage: "checkmark")
                    } else {
                        Text(v.name)
                    }
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: plaene.wahl == nil ? "location.fill" : "pin.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(plaene.verbund?.name ?? "Fahrpläne für ganz Deutschland")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 14) {
                    Image("Symbol")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Gleich")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                }
                .padding(.top, 20)

                verbundWahl

                if !plaene.plaene.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                              spacing: 14) {
                        ForEach(plaene.plaene) { p in
                            Button { offen = p } label: {
                                PlanKachel(plan: p, bereit: plaene.istBereit(p))
                            }
                            .buttonStyle(.plain)
                            .disabled(!plaene.istBereit(p))
                        }
                    }
                }

                AnleitungKasten()

                Text("Daten: Transitous\(quelleVBB ? " · VBB" : "")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(item: $offen) { p in
            PlanAnsicht(plan: p)
        }
    }
}

struct PlanKachel: View {
    var plan: Netzplan
    var bereit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                if bereit, let bild = PlanKachel.vorschau(plan) {
                    Image(uiImage: bild)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Lok(ruckelt: true).scaleEffect(0.7)
                }
            }
            .frame(height: 110)
            Text(plan.titel)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private static var zwischenspeicher: [String: UIImage] = [:]

    static func vorschau(_ p: Netzplan) -> UIImage? {
        if let b = zwischenspeicher[p.id] { return b }
        guard let doc = PDFDocument(url: p.datei), let seite = doc.page(at: 0) else { return nil }
        let bild = seite.thumbnail(of: CGSize(width: 360, height: 360), for: .mediaBox)
        zwischenspeicher[p.id] = bild
        return bild
    }
}

/// Plan bildschirmfüllend, zum Zoomen. Titel und Kreuz liegen in einer eigenen Leiste über dem Plan –
/// als Schicht über dem PDF kamen Berührungen beim Kreuz nicht an.
struct PlanAnsicht: View {
    var plan: Netzplan
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(plan.titel)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button { schliessen() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            PDFAnsicht(url: plan.datei)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Color(.systemBackground))
    }
}

struct PDFAnsicht: UIViewRepresentable {
    var url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = PDFDocument(url: url)
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .systemBackground
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {}
}

/// Kurze Anleitung – auf der Übersicht und beim ersten Start.
struct AnleitungKasten: View {
    private let punkte: [(String?, String)] = [
        (nil, "Oben die nächste Haltestelle, darunter was abfährt."),
        ("Rot:", "verspätet, das ist die echte Abfahrt."),
        ("Blass:", "zu Fuß wohl nicht mehr zu schaffen."),
        ("Nach links wischen:", "andere Haltestellen in der Nähe."),
        ("Nach rechts wischen:", "diese Übersicht."),
        ("Runterziehen:", "aktualisieren."),
        ("Abfahrt antippen:", "alle weiteren Halte."),
        ("Haltestellenname antippen:", "Fußweg dorthin."),
        ("Lange drücken:", "Ort merken."),
        ("Verbundname antippen:", "andere Netzpläne wählen."),
        ("Wohin?", "Verbindungen von hier; die Uhr daneben wählt die Abfahrtszeit."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anleitung")
                .font(.headline)
            ForEach(punkte.indices, id: \.self) { i in
                let (fett, rest) = punkte[i]
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    (fett.map { Text($0 + " ").fontWeight(.semibold) } ?? Text("")) + Text(rest)
                }
                .font(.subheadline)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Beim ersten Start: die Anleitung als Kasten, weg mit „OK“.
struct AnleitungHinweis: View {
    var fertig: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture(perform: fertig)
            VStack(spacing: 16) {
                AnleitungKasten()
                Button(action: fertig) {
                    Text("OK")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.glassProminent)
            }
            .padding(20)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 20)
        }
    }
}
