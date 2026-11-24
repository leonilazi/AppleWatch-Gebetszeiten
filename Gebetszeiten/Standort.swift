import Foundation
import CoreLocation
import Combine


// MARK: - Standort des Geräts

@MainActor
final class StandortManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    // bestimmt, wo sich das iPhone bzw. die Uhr gerade befindet
    // ObservableObject = SwiftUI merkt, wenn sich der Standort ändert, und rechnet neu
    // gleicher Aufbau wie die Klasse Kompass in Qibla.swift

    @Published var latitude: Double
    @Published var longitude: Double
    @Published var name: String
    // Name des Orts, z. B. "Zürich", wird unten in der Gebetszeiten-Liste angezeigt

    @Published var version = 0
    // zählt jede Änderung des Standorts
    // so merken die Ansichten, dass sie die Gebetszeiten neu berechnen müssen

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    // CLGeocoder macht aus Koordinaten einen Ortsnamen (z. B. 47.37 / 8.54 --> "Zürich")

    override init() {

        // zuerst den zuletzt gespeicherten Standort laden
        // so zeigt die App sofort Zeiten an, auch ohne GPS-Empfang
        let speicher = UserDefaults.standard
        // UserDefaults = kleiner Speicher der App, bleibt auch nach dem Schliessen erhalten

        if speicher.object(forKey: "latitude") != nil {
            latitude = speicher.double(forKey: "latitude")
            longitude = speicher.double(forKey: "longitude")
            name = speicher.string(forKey: "ortsname") ?? "Mein Standort"
        } else {
            // erster Start: noch nichts gespeichert, also Zürich als Startwert
            latitude = 47.37
            longitude = 8.54
            name = "Zürich"
        }

        super.init()

        manager.delegate = self
        // delegate = self bedeutet: neue Standorte sollen an diese Klasse geschickt werden

        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        // 1 km Genauigkeit reicht völlig
        // 1 km Unterschied verschiebt die Gebetszeiten nur um wenige Sekunden
        // und eine ungenauere Ortung spart Akku
    }

    func aktualisieren() {
        // fragt den aktuellen Standort ab
        // wird beim Start der App und jedes Mal beim Öffnen aufgerufen

        switch manager.authorizationStatus {

        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // der Benutzer wurde noch nie gefragt --> Erlaubnis anfragen
            // (zeigt den Text aus "Privacy - Location When In Use Usage Description")

        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
            // Standort einmal abfragen (nicht dauernd, das spart Akku)

        default:
            break
            // Erlaubnis verweigert --> der gespeicherte Standort bzw. Zürich bleibt
        }
    }

    func neuerStandort(_ ort: CLLocation) {

        let bisherigerOrt = CLLocation(latitude: latitude, longitude: longitude)

        if ort.distance(from: bisherigerOrt) < 1000 && version > 0 {
            return
            // weniger als 1 km bewegt --> nichts neu berechnen
        }

        latitude = ort.coordinate.latitude
        longitude = ort.coordinate.longitude
        version += 1
        // dadurch berechnen die Ansichten die Zeiten und die Qibla neu

        let speicher = UserDefaults.standard
        speicher.set(latitude, forKey: "latitude")
        speicher.set(longitude, forKey: "longitude")
        // speichern, damit der Standort beim nächsten Start sofort da ist

        Task {
            // Ortsnamen im Hintergrund suchen (braucht Internet)
            if let orte = try? await geocoder.reverseGeocodeLocation(ort),
               let stadt = orte.first?.locality {
                // locality = Ortschaft, z. B. "Winterthur"
                name = stadt
            } else {
                name = "Mein Standort"
                // kein Internet oder kein Name gefunden
            }
            speicher.set(name, forKey: "ortsname")
        }
    }

    // MARK: - Antworten vom CLLocationManager

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // wird aufgerufen, sobald der Benutzer "Erlauben" oder "Nicht erlauben" gewählt hat
        Task { @MainActor in
            self.aktualisieren()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // wird aufgerufen, sobald ein neuer Standort gefunden wurde

        guard let ort = locations.last else { return }
        // last = der neueste Standort in der Liste

        Task { @MainActor in
            self.neuerStandort(ort)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Standort konnte nicht bestimmt werden (z. B. in einem Gebäude ohne Empfang)
        // dann bleibt einfach der letzte bekannte Standort
        // diese Funktion muss es geben, sonst stürzt die App bei requestLocation() ab
    }
}
