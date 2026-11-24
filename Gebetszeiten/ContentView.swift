import SwiftUI

// MARK: - Farben der App

enum Farben {
    static let akzent = Color(red: 0.18, green: 0.62, blue: 0.42)
    // Grün für das nächste Gebet und die richtige Qibla-Richtung
    static let gold = Color(red: 0.85, green: 0.70, blue: 0.35)
    // Gold für Symbole und den Qibla-Pfeil
}

// MARK: - Startseite

struct ContentView: View {

    @StateObject private var standort = StandortManager()
    // der Standort wird hier einmal erstellt und an beide Seiten weitergegeben

    @Environment(\.scenePhase) private var phase
    // scenePhase sagt, ob die App gerade offen (.active) oder im Hintergrund ist

    #if os(iOS)
    init() {
        // Farben der Seitenpunkte unten auf dem iPhone
        // Apple macht den aktiven Punkt standardmässig weiss (gedacht für dunklen Hintergrund)
        // auf weissem Hintergrund sah es deshalb vertauscht aus
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(Farben.akzent)
        // aktive Seite = grün
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.systemGray3
        // andere Seite = hellgrau
    }
    #endif

    var body: some View {
        TabView {
            GebetszeitenView()
            QiblaView()
        }
        #if os(watchOS)
        .tabViewStyle(.page)
        // auf der Uhr: zwei Seiten nebeneinander, mit Wischen nach links oder rechts wechseln
        // (seitwärts, damit es sich nicht mit dem Scrollen der Liste in die Quere kommt)
        #elseif os(iOS)
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        // auf dem iPhone: zwei Seiten nebeneinander, Punkte unten ohne grauen Hintergrund
        #endif
        .environmentObject(standort)
        // environmentObject = beide Seiten können über @EnvironmentObject auf den Standort zugreifen
        .onAppear {
            standort.aktualisieren()
        }
        .onChange(of: phase) { _, neuePhase in
            if neuePhase == .active {
                standort.aktualisieren()
                // jedes Mal, wenn man die App wieder öffnet, den Standort neu abfragen
            }
        }
    }
}

#Preview {
    ContentView()
}

