import Foundation

enum Netz {
    /// Transitous möchte wissen, wer anfragt. Kontakt ist die Projektseite, nicht eine Mailadresse.
    static let kennung = "Gleich-iOS/1.0 (+https://github.com/felixmoniac/gleich)"

    static let sitzung: URLSession = {
        let k = URLSessionConfiguration.default
        k.timeoutIntervalForRequest = 12
        k.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: k)
    }()

    static func json(_ basis: String, _ pfad: String, _ parameter: [String: String?]) async throws -> Any {
        var teile = URLComponents(string: basis + pfad)!
        teile.queryItems = parameter.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        // „+“ würde sonst als Leerzeichen gelesen (Zeitangaben mit Zeitzone).
        teile.percentEncodedQuery = teile.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var anfrage = URLRequest(url: teile.url!)
        anfrage.setValue(kennung, forHTTPHeaderField: "User-Agent")
        anfrage.setValue("application/json", forHTTPHeaderField: "Accept")
        let (daten, antwort) = try await sitzung.data(for: anfrage)
        guard let http = antwort as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONSerialization.jsonObject(with: daten)
    }
}

// Kleine Helfer zum Lesen von lose getipptem JSON.
extension Dictionary where Key == String, Value == Any {
    func text(_ k: String) -> String? {
        if let s = self[k] as? String, !s.isEmpty { return s }
        if let n = self[k] as? NSNumber { return n.stringValue }
        return nil
    }
    func zahl(_ k: String) -> Double? { (self[k] as? NSNumber)?.doubleValue }
    func objekt(_ k: String) -> [String: Any]? { self[k] as? [String: Any] }
    func liste(_ k: String) -> [[String: Any]] { self[k] as? [[String: Any]] ?? [] }
    func wahr(_ k: String) -> Bool { (self[k] as? Bool) ?? false }
    func datum(_ k: String) -> Date? { text(k).flatMap(Zeit.lesen) }
}

enum Zeit {
    private static let mitBruch: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let ohneBruch: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func lesen(_ s: String) -> Date? { ohneBruch.date(from: s) ?? mitBruch.date(from: s) }
    static func schreiben(_ d: Date) -> String { ohneBruch.string(from: d) }

    static let uhr: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "H:mm"
        return f
    }()

    /// „14:30“, „morgen 8:15“ oder „Fr. 8:15“ – für gewählte Abfahrtszeiten.
    static func wann(_ d: Date) -> String {
        let k = Calendar.current
        if k.isDateInToday(d) { return uhr.string(from: d) }
        if k.isDateInTomorrow(d) { return "morgen " + uhr.string(from: d) }
        let tag = DateFormatter()
        tag.locale = Locale(identifier: "de_DE")
        tag.dateFormat = "EE d.M. H:mm"
        return tag.string(from: d)
    }

    /// „jetzt“, „4 Min“ oder ab einer Stunde die Uhrzeit.
    static func bis(_ d: Date, ab jetzt: Date = .now) -> String {
        let min = Int((d.timeIntervalSince(jetzt) / 60).rounded(.down))
        if min < 1 { return "jetzt" }
        if min < 60 { return "\(min) Min" }
        return uhr.string(from: d)
    }
}
