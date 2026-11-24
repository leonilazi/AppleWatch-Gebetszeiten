import Foundation
import CoreLocation
import Combine

// MARK: - Position der Kaaba

let kaabaLatitude = 21.4225
let kaabaLongitude = 39.8262
// geografische Koordinaten der Kaaba in Mekka

// MARK: - Qibla-Richtung

func qiblaRichtung(latitude: Double, longitude: Double) -> Double {
    // berechnet die Richtung nach Mekka in Grad
    // 0 = Norden, 90 = Osten, 180 = Süden, 270 = Westen
    // es wird der kürzeste Weg über die Erdkugel genommen (Grosskreis)
    // deshalb ist die Richtung nicht einfach "geradeaus auf der Landkarte"

    let phi = degToRad(latitude)
    // eigener Breitengrad im Bogenmass

    let phiKaaba = degToRad(kaabaLatitude)
    // Breitengrad der Kaaba im Bogenmass

    let deltaLambda = degToRad(kaabaLongitude - longitude)
    // Unterschied der Längengrade zwischen Kaaba und eigenem Standort

    let y = sin(deltaLambda)
    let x = cos(phi) * tan(phiKaaba) - sin(phi) * cos(deltaLambda)
    // Formel für die Richtung auf der Kugel

    let richtung = radToDeg(atan2(y, x))
    // atan2 statt atan, weil atan2 den richtigen Quadranten automatisch erkennt
    // (bei solarHeight musste man das bei alpha noch von Hand machen)

    return richtung - 360 * floor(richtung / 360)
    // bringt die Richtung in den Bereich 0 bis unter 360 Grad
    // Beispiel: aus -30° wird 330°
}

func distanzZurKaaba(latitude: Double, longitude: Double) -> Double {
    // berechnet die Entfernung zur Kaaba in Kilometern (Luftlinie über die Erdkugel)

    let phi = degToRad(latitude)
    let phiKaaba = degToRad(kaabaLatitude)
    let deltaLambda = degToRad(kaabaLongitude - longitude)

    let winkel = acos(sin(phi) * sin(phiKaaba) + cos(phi) * cos(phiKaaba) * cos(deltaLambda))
    // Winkel zwischen den beiden Orten, vom Erdmittelpunkt aus gesehen

    let erdradius = 6371.0
    // mittlerer Erdradius in Kilometern

    return winkel * erdradius
    // Bogenlänge = Winkel (im Bogenmass) * Radius
}

func himmelsrichtung(_ grad: Double) -> String {
    // macht aus einer Gradzahl eine Himmelsrichtung
    // Beispiel: 125° --> "SO"

    let namen = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
    // 8 Richtungen, jede deckt 45 Grad ab (360 / 8 = 45)

    let index = Int((grad + 22.5) / 45) % 8
    // + 22.5, damit z. B. Norden von 337.5° bis 22.5° geht und nicht von 0° bis 45°
    // % 8, damit aus 8 wieder 0 wird (360° ist wieder Norden)

    return namen[index]
}

// MARK: - Kompass der Uhr

@MainActor
final class Kompass: NSObject, ObservableObject, CLLocationManagerDelegate {
    // liest den Kompass der Apple Watch aus (ab Apple Watch Series 5)
    // ObservableObject = SwiftUI merkt, wenn sich ein Wert ändert, und zeichnet neu

    @Published var richtung: Double? = nil
    // wohin die Uhr gerade zeigt, in Grad (0 = Norden)
    // nil, wenn es keinen Kompass gibt (z. B. im Simulator)

    private let manager = CLLocationManager()
    // CLLocationManager ist die Schnittstelle von Apple für Standort und Kompass

    override init() {
        super.init()
        manager.delegate = self
        // delegate = self bedeutet: die neuen Kompasswerte sollen an diese Klasse geschickt werden
        manager.headingFilter = 1
        // nur melden, wenn sich die Richtung um mindestens 1 Grad ändert (spart Akku)
    }

    func starten() {
        if CLLocationManager.headingAvailable() {
            // nur starten, wenn die Uhr überhaupt einen Kompass hat
            manager.startUpdatingHeading()
        }
    }

    func stoppen() {
        manager.stopUpdatingHeading()
        // Kompass ausschalten, wenn man die Seite verlässt (spart Akku)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // wird automatisch aufgerufen, sobald der Kompass einen neuen Wert hat

        guard newHeading.headingAccuracy >= 0 else { return }
        // negative Genauigkeit bedeutet: der Wert ist ungültig

        let wert: Double
        if newHeading.trueHeading >= 0 {
            wert = newHeading.trueHeading
            // geografischer Norden
        } else {
            wert = newHeading.magneticHeading
            // magnetischer Norden, falls der geografische nicht verfügbar ist
            // in der Schweiz ist der Unterschied nur etwa 3 Grad
        }

        Task { @MainActor in
            self.richtung = wert
            // Anzeige-Werte dürfen nur auf dem Hauptthread geändert werden
        }
    }
}
