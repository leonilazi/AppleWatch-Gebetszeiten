import SwiftUI

struct Eintrag: Identifiable {
    // eine Zeile in der Liste
    // Identifiable = jede Zeile hat eine eindeutige id, damit ForEach sie unterscheiden kann
    var id: String { name }
    let name: String
    let symbol: String
    // Name eines Apple-Symbols (SF Symbols), z. B. "sunrise"
    let zeit: Date
    let istGebet: Bool
    // der Sonnenaufgang ist kein Gebet, er wird nur angezeigt
}

struct GebetszeitenView: View {

    @EnvironmentObject var standort: StandortManager
    // der Standort kommt von der ContentView

    @State private var heute: Gebetszeiten?
    @State private var morgen: Gebetszeiten?
    // morgen wird gebraucht, damit nach Isha der Fajr von morgen als nächstes Gebet erscheint

    var body: some View {

        TimelineView(.periodic(from: .now, by: 30)) { kontext in
            // TimelineView zeichnet die Anzeige alle 30 Sekunden neu,
            // damit immer das richtige nächste Gebet markiert ist

            Group {
                if let heute = heute, let morgen = morgen {
                    inhalt(heute: heute, morgen: morgen, jetzt: kontext.date)
                } else {
                    ProgressView()
                    // Ladekreis, solange noch gerechnet wird
                }
            }
            .onChange(of: Calendar.current.component(.day, from: kontext.date)) { _, _ in
                berechnen()
                // nach Mitternacht werden die Zeiten für den neuen Tag berechnet
            }
        }
        .onAppear {
            berechnen()
        }
        .onChange(of: standort.version) { _, _ in
            berechnen()
            // neuer Standort --> Zeiten neu berechnen
        }
    }

    func berechnen() {
        let jetzt = Date()
        heute = berechneGebetszeiten(at: jetzt, latitude: standort.latitude, longitude: standort.longitude)
        morgen = berechneGebetszeiten(at: tagVerschieben(jetzt, um: 1), latitude: standort.latitude, longitude: standort.longitude)
    }

    func eintraege(_ z: Gebetszeiten) -> [Eintrag] {
        // macht aus den Gebetszeiten eine Liste, die man anzeigen kann
        return [
            Eintrag(name: "Fajr", symbol: "moon.stars", zeit: z.fajr, istGebet: true),
            Eintrag(name: "Sonnenaufgang", symbol: "sunrise", zeit: z.sonnenaufgang, istGebet: false),
            Eintrag(name: "Dhuhr", symbol: "sun.max", zeit: z.dhuhr, istGebet: true),
            Eintrag(name: "Asr", symbol: "sun.min", zeit: z.asr, istGebet: true),
            Eintrag(name: "Maghrib", symbol: "sunset", zeit: z.maghrib, istGebet: true),
            Eintrag(name: "Isha", symbol: "moon", zeit: z.isha, istGebet: true)
        ]
    }

    func inhalt(heute: Gebetszeiten, morgen: Gebetszeiten, jetzt: Date) -> some View {

        let liste = eintraege(heute)

        let naechstes = liste.first { $0.istGebet && $0.zeit > jetzt }
            ?? Eintrag(name: "Fajr", symbol: "moon.stars", zeit: morgen.fajr, istGebet: true)
        // das erste Gebet, das noch nicht vorbei ist
        // ?? = falls heute keines mehr kommt (nach Isha), nimm Fajr von morgen

        return ScrollView {
            VStack(spacing: 6) {

                // Kopfbereich mit dem nächsten Gebet
                VStack(spacing: 0) {
                    Text("NÄCHSTES GEBET")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(naechstes.name)
                        .font(.title2.bold())
                        .foregroundStyle(Farben.akzent)

                    Text(naechstes.zeit, style: .timer)
                        .font(.title3.monospacedDigit())
                    // zählt automatisch rückwärts bis zum nächsten Gebet
                }
                .padding(.bottom, 4)

                ForEach(liste) { eintrag in
                    zeile(eintrag,
                          istNaechstes: eintrag.zeit == naechstes.zeit,
                          istVorbei: eintrag.zeit < jetzt)
                }

                Label("\(standort.name) · \(jetzt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))",
                      systemImage: "location.fill")
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            #if os(iOS)
            .padding()
            .frame(maxWidth: 420)
            // auf dem iPhone etwas Rand und nicht zu breit
            #endif
        }
    }

    func zeile(_ eintrag: Eintrag, istNaechstes: Bool, istVorbei: Bool) -> some View {
        // eine Zeile: Symbol, Name und Uhrzeit
        // das nächste Gebet wird grün hinterlegt, vergangene Zeiten werden grau

        let textFarbe: Color
        if istNaechstes {
            textFarbe = .black
        } else if istVorbei {
            textFarbe = .secondary
        } else {
            textFarbe = .primary
        }
        // .primary = schwarz im hellen Modus (iPhone), weiss im dunklen Modus (Uhr)

        return HStack(spacing: 8) {

            Image(systemName: eintrag.symbol)
                .frame(width: 20)
                .foregroundStyle(istNaechstes ? Color.black : Farben.gold)

            Text(eintrag.name)
                .font(.system(size: 15, weight: istNaechstes ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // lineLimit + minimumScaleFactor: "Sonnenaufgang" wird bei Bedarf etwas kleiner statt abgeschnitten

            Spacer()

            Text(uhrzeitText(eintrag.zeit))
                .font(.system(size: 15, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(textFarbe)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(istNaechstes ? Farben.akzent : Color.primary.opacity(0.08))
        )
    }
}

func uhrzeitText(_ date: Date) -> String {
    let sekunden = date.timeIntervalSince1970
    let aufgerundet = ceil(sekunden / 60.0) * 60.0
    let gerundetesDatum = Date(timeIntervalSince1970: aufgerundet)

    let formatierer = DateFormatter()
    formatierer.dateFormat = "HH:mm"
    formatierer.timeZone = .current

    return formatierer.string(from: gerundetesDatum)
}
