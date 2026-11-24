//
//  Gebetszeiten_WatchApp.swift
//  Gebetszeiten Watch Watch App
//
//  Created by Jon Ilazi on 27.10.2026.
//

import SwiftUI
enum Farben {
    static let akzent = Color(red: 0.18, green: 0.62, blue: 0.42)
    // Grün für das nächste Gebet und die richtige Qibla-Richtung
    static let gold = Color(red: 0.85, green: 0.70, blue: 0.35)
    // Gold für Symbole und den Qibla-Pfeil
}
@main
struct Gebetszeiten_Watch_Watch_AppApp: App {
    @StateObject private var standort = StandortManager()
    
    var body: some Scene {
        WindowGroup {
            TabView {
                GebetszeitenView()
                    .tabItem {
                        Label("Gebetszeiten", systemImage: "clock")
                    }
                QiblaView()
                    .tabItem {
                        Label("QIbla", systemImage: "location.north")
                    }
            }
            .environmentObject(standort)
        }
    }
}
