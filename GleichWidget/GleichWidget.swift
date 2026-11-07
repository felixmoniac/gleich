import WidgetKit
import SwiftUI
import CoreLocation

struct Eintrag: TimelineEntry {
    var date: Date
    var halt: String?
    var abfahrten: [Abfahrt]
    var jwd = false
}

struct Lieferant: TimelineProvider {
    func placeholder(in context: Context) -> Eintrag { Eintrag.beispiel }

    func getSnapshot(in context: Context, completion: @escaping (Eintrag) -> Void) {
        if context.isPreview { completion(.beispiel); return }
        Task { completion(await Lieferant.holen().first ?? .beispiel) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Eintrag>) -> Void) {
        Task {
            let eintraege = await Lieferant.holen()
            completion(Timeline(entries: eintraege, policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }

    /// Ein Eintrag pro Minute für die nächste Viertelstunde, damit die Minuten mitzählen.
    static func holen() async -> [Eintrag] {
        let jetzt = Date.now
        guard let ort = await ort() else {
            return [Eintrag(date: jetzt, halt: nil, abfahrten: [])]
        }
        guard let alle = try? await Fahrplan.kandidaten(bei: ort.coordinate), !alle.isEmpty else {
            return [Eintrag(date: jetzt, halt: nil, abfahrten: [])]
        }
        // Echte Fußwege wie in der App; Widgets haben wenig Zeit, deshalb kürzere Frist.
        let wege = await Gehwege.zeiten(von: ort, zu: Gehwege.auswahl(alle, um: ort), frist: 5)
        let gehzeit = { (h: Haltestelle) in wege[h.id] ?? Fahrplan.gehzeit(von: ort, zu: h) }
        guard let halt = Fahrplan.auswaehlen(alle, gehzeit: gehzeit).first else {
            return [Eintrag(date: jetzt, halt: nil, abfahrten: [])]
        }
        if halt.ort.distance(from: ort) > Fahrplan.jwdMeter {
            return [Eintrag(date: jetzt, halt: nil, abfahrten: [], jwd: true)]
        }
        let abfahrten = (try? await Fahrplan.abfahrten(halt).abfahrten) ?? []
        let gehen = gehzeit(halt)
        let ortsname = Namen.ort(aus: halt.name)
        let liste = abfahrten
            .filter { !$0.faelltAus }
            .map { a in var a = a; a.richtung = Namen.kurz(a.richtung, ort: ortsname); return a }
        return (0..<15).map { m in
            let zeit = jetzt.addingTimeInterval(Double(m) * 60)
            // Nur, was man zu Fuß noch schafft.
            let rest = liste.filter { $0.zeit.timeIntervalSince(zeit) >= gehen }
            return Eintrag(date: zeit, halt: Namen.kurz(halt.name), abfahrten: Array(rest.prefix(3)))
        }
    }

    private static func ort() async -> CLLocation? {
        let m = CLLocationManager()
        if m.isAuthorizedForWidgetUpdates {
            let frisch = await withTaskGroup(of: CLLocation?.self) { g in
                g.addTask {
                    do {
                        for try await u in CLLocationUpdate.liveUpdates() {
                            if let o = u.location { return o }
                        }
                    } catch {}
                    return nil
                }
                g.addTask {
                    try? await Task.sleep(for: .seconds(6))
                    return nil
                }
                let erstes = await g.next() ?? nil
                g.cancelAll()
                return erstes
            }
            if let frisch { return frisch }
            if let alt = m.location { return alt }
        }
        return Ablage.letzterOrt
    }
}

extension Eintrag {
    static let beispiel = Eintrag(
        date: .now,
        halt: "Potsdam Hauptbahnhof",
        abfahrten: [
            Abfahrt(id: "1", linie: Linie(name: "S7", mittel: .sbahn, farbe: "816da6"), richtung: "Ahrensfelde",
                    geplant: .now.addingTimeInterval(240), echt: nil, gleis: nil, faelltAus: false,
                    fahrtID: "", quelle: .vbb, halt: ""),
            Abfahrt(id: "2", linie: Linie(name: "96", mittel: .tram), richtung: "Campus Jungfernsee",
                    geplant: .now.addingTimeInterval(420), echt: nil, gleis: nil, faelltAus: false,
                    fahrtID: "", quelle: .vbb, halt: ""),
            Abfahrt(id: "3", linie: Linie(name: "695", mittel: .bus), richtung: "Science Park West",
                    geplant: .now.addingTimeInterval(660), echt: nil, gleis: nil, faelltAus: false,
                    fahrtID: "", quelle: .vbb, halt: ""),
        ]
    )
}

struct WidgetAnsicht: View {
    var eintrag: Eintrag
    @Environment(\.widgetFamily) private var familie

    var body: some View {
        switch familie {
        case .accessoryRectangular: sperrbildschirm
        default: klein
        }
    }

    private var klein: some View {
        VStack(alignment: .leading, spacing: 7) {
            if eintrag.jwd {
                Spacer()
                Text("JWD – dit tut weh")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Spacer()
            } else if let halt = eintrag.halt {
                Text(halt)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .lineLimit(1)
                ForEach(eintrag.abfahrten) { a in
                    HStack(spacing: 6) {
                        LinienSymbol(linie: a.linie, klein: true)
                        Text(a.richtung)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(Zeit.bis(a.zeit, ab: eintrag.date).replacingOccurrences(of: " Min", with: "'"))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(a.verspaetet ? Color.red : Color.primary)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer()
                Image(systemName: "location.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }

    private var sperrbildschirm: some View {
        VStack(alignment: .leading, spacing: 2) {
            if eintrag.jwd {
                Text("JWD – dit tut weh").font(.headline)
            } else {
                ForEach(eintrag.abfahrten.prefix(2)) { a in
                    HStack(spacing: 6) {
                        Text(a.linie.name)
                            .font(.headline)
                            .frame(minWidth: 34, alignment: .leading)
                        Text(a.richtung)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(Zeit.bis(a.zeit, ab: eintrag.date).replacingOccurrences(of: " Min", with: "'"))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

struct GleichWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GleichWidget", provider: Lieferant()) { e in
            WidgetAnsicht(eintrag: e)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Gleich")
        .description("Die nächsten Abfahrten an der Haltestelle in deiner Nähe.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

@main
struct GleichWidgets: WidgetBundle {
    var body: some Widget {
        GleichWidget()
        FahrtLive()
    }
}

#Preview(as: .systemSmall) { GleichWidget() } timeline: { Eintrag.beispiel }
