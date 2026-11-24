import SwiftUI
#if os(watchOS)
import WatchKit
// WatchKit gibt es nur auf der Apple Watch (für die Vibration)
#elseif os(iOS)
import UIKit
// UIKit braucht es auf dem iPhone für die Vibration
#endif

struct QiblaView: View {

    @StateObject private var kompass = Kompass()
    // @StateObject = SwiftUI erstellt den Kompass einmal und behält ihn

    @EnvironmentObject var standort: StandortManager
    // der Standort kommt von der ContentView

    var qibla: Double {
        qiblaRichtung(latitude: standort.latitude, longitude: standort.longitude)
    }
    // var mit { } = wird jedes Mal neu berechnet, also auch nach einem neuen Standort

    var distanz: Double {
        distanzZurKaaba(latitude: standort.latitude, longitude: standort.longitude)
    }

    #if os(watchOS)
    let radius: Double = 60
    #else
    let radius: Double = 130
    #endif
    // Radius der Kompassrose in Punkten
    // auf dem iPhone ist der Bildschirm grösser, deshalb ist die Rose dort grösser

    var body: some View {

        let blick = kompass.richtung ?? 0
        // wohin das Gerät zeigt (0 = Norden)
        // ohne Kompass nehmen wir an, dass das Gerät nach Norden zeigt

        let differenz = normalisiereWinkel(qibla - blick)
        // um wie viel Grad man sich noch drehen muss (aus Gebetszeiten.swift)
        // Beispiel: Qibla 125°, Gerät zeigt 100° --> noch 25° nach rechts drehen

        let ausgerichtet = kompass.richtung != nil && abs(differenz) < 5
        // true, wenn man weniger als 5 Grad neben der Qibla steht

        VStack(spacing: 6) {

            ZStack {
                // ZStack = Elemente übereinander

                kompassRose
                    .rotationEffect(.degrees(-blick))
                // die Rose dreht sich entgegen dem Gerät, damit N immer nach Norden zeigt

                Image(systemName: "location.north.fill")
                    .font(.system(size: radius * 0.55))
                // Pfeilgrösse passt sich der Rose an
                    .foregroundStyle(ausgerichtet ? Farben.akzent : Farben.gold)
                    .rotationEffect(.degrees(differenz))
                // der Pfeil zeigt immer Richtung Mekka
            }
            .frame(width: radius * 2, height: radius * 2)
            .animation(.easeOut(duration: 0.2), value: blick)

            if ausgerichtet {
                Text("Richtung stimmt")
                    .font(.headline)
                    .foregroundStyle(Farben.akzent)
            } else {
                Text("Qibla \(Int(qibla.rounded()))° \(himmelsrichtung(qibla))")
                    .font(.headline)
            }

            if kompass.richtung == nil {
                Text("Kein Kompass – Norden ist oben")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(Int(distanz.rounded())) km bis Mekka")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            kompass.starten()
        }
        .onDisappear {
            kompass.stoppen()
        }
        .onChange(of: ausgerichtet) { _, jetztAusgerichtet in
            // wird aufgerufen, wenn sich ausgerichtet ändert
            #if os(watchOS)
            if jetztAusgerichtet {
                WKInterfaceDevice.current().play(.success)
                // die Uhr vibriert kurz, sobald man richtig steht
            }
            #elseif os(iOS)
            if jetztAusgerichtet {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // das iPhone vibriert kurz, sobald man richtig steht
            }
            #endif
        }
    }

    var kompassRose: some View {
        // Kreis mit Strichen, N-Markierung und Kaaba-Symbol

        ZStack {

            Circle()
                .stroke(Color.primary.opacity(0.25), lineWidth: 2)
            // Color.primary = schwarz im hellen Modus, weiss im dunklen Modus

            ForEach(0..<12) { i in
                // 12 Striche, also alle 30 Grad einer (360 / 12 = 30)
                // jeder dritte Strich (0°, 90°, 180°, 270°) ist länger und heller
                Capsule()
                    .fill(Color.primary.opacity(i % 3 == 0 ? 0.8 : 0.3))
                    .frame(width: 2, height: i % 3 == 0 ? 10 : 6)
                    .offset(y: -(radius - 6))
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            Text("N")
                .font(.caption2.bold())
                .foregroundStyle(.red)
                .offset(y: -(radius - 18))

            Image(systemName: "cube.fill")
                .font(.system(size: 12))
                .foregroundStyle(Farben.gold)
                .offset(y: -radius)
                .rotationEffect(.degrees(qibla))
            // das Kaaba-Symbol sitzt am Rand genau in Qibla-Richtung
        }
    }
}
