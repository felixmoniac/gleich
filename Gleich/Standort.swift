import CoreLocation
import Observation

@Observable
final class Standort: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var warten: [CheckedContinuation<CLLocation?, Never>] = []

    var erlaubnis: CLAuthorizationStatus
    var ort: CLLocation?

    var verweigert: Bool { erlaubnis == .denied || erlaubnis == .restricted }
    var erlaubt: Bool { erlaubnis == .authorizedWhenInUse || erlaubnis == .authorizedAlways }

    override init() {
        erlaubnis = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // Auf 100 m genau reicht für „welche Haltestellen sind in der Nähe“ – und kommt meist in einer Sekunde
        // statt nach mehreren, weil das iPhone dafür nicht erst auf GPS warten muss.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        ort = manager.location ?? Ablage.letzterOrt
    }

    func fragen() {
        if erlaubnis == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    /// Holt einen frischen Standort; nach spätestens 8 Sekunden gilt der letzte bekannte.
    func frisch() async -> CLLocation? {
        if erlaubnis == .notDetermined {
            fragen()
            // Warten, bis die Frage beantwortet ist.
            for _ in 0..<600 where erlaubnis == .notDetermined {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        guard erlaubt else { return nil }
        // Kennt das iPhone schon einen frischen Standort (keine zwei Minuten alt), gilt der sofort.
        if let l = manager.location, -l.timestamp.timeIntervalSinceNow < 120,
           l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 150 {
            ort = l
            Ablage.letzterOrt = l
            return l
        }
        let neu: CLLocation? = await withCheckedContinuation { c in
            warten.append(c)
            if warten.count == 1 { manager.requestLocation() }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                self.fertig(self.manager.location)
            }
        }
        return neu ?? ort
    }

    private func fertig(_ o: CLLocation?) {
        if let o {
            ort = o
            Ablage.letzterOrt = o
        }
        let alle = warten
        warten = []
        alle.forEach { $0.resume(returning: o) }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations orte: [CLLocation]) {
        Task { @MainActor in self.fertig(orte.last) }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.fertig(m.location) }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in self.erlaubnis = m.authorizationStatus }
    }
}
