import Foundation

// MARK: - Einstellungen nach FIDS (FAQ SwissMosque)

let breitengradGrenze = 44.5
// ab diesem Breitengrad werden die bestimmten Zeiten angewendet
// die ganze Schweiz liegt darüber (ca. 45.8° bis 47.8°)

let minimaleDauer: TimeInterval = 5 * 3600
// Tag und Nacht dürfen nie kürzer als 5 Stunden sein
// 5 * 3600, weil eine Stunde 3600 Sekunden hat

let uebergang: TimeInterval = 20 * 60
// 20 Minuten für den schrittweisen Übergang von tatsächlichen zu bestimmten Zeiten

// Tamkin = Sicherheitsminuten, die am Schluss zu den berechneten Zeiten dazugerechnet werden
let tamkinFajr: TimeInterval = 0
let tamkinSonnenaufgang: TimeInterval = -7 * 60
// beim Sonnenaufgang wird abgezogen, damit das Ende des Fajr-Gebets sicher vor dem Aufgang liegt
let tamkinDhuhr: TimeInterval = 5 * 60
// das sind die gleichen 5 Minuten, die im Dokument bei Dhuhr erwähnt werden (nicht doppelt rechnen)
let tamkinAsr: TimeInterval = 4 * 60
let tamkinMaghrib: TimeInterval = 7 * 60
let tamkinIsha: TimeInterval = 0

// MARK: - Sonnenstand

func solarHeight(at date: Date, latitude: Double, longitude: Double) -> (h: Double, tau: Double, delta: Double) {

    let unixSeconds = date.timeIntervalSince1970

    let JD = unixSeconds / 86400.0 + 2440587.5

    let n = JD - 2451545.0

    let g = 357.528 + 0.9856003 * n

    let epsilon = 23.439 - 0.000000356 * n

    let L = 280.460 + 0.9856474 * n

    let gRad = degToRad(g)

    let lambdaSun = L + 1.91368 * sin(gRad) + 0.01997 * sin(2 * gRad) + 0.00029 * sin(3 * gRad)

    let epsilonRad = degToRad(epsilon)

    let delta = radToDeg(asin(sin(epsilonRad) * sin(degToRad(lambdaSun))))

    let baseAlpha = radToDeg(atan(cos(epsilonRad) * tan(degToRad(lambdaSun))))

    let alpha: Double // hier ist Double notwendig, da Swift es nicht automatisch erkennt

    if cos(degToRad(lambdaSun)) > 0 {
        alpha = baseAlpha
    } else {
        alpha = baseAlpha + 180
    }

    let fracN = n - floor(n)
    // macht, dass man nur die Nachkommazahl von n erhält Bsp: 3.75 --> 0.75

    let thetaGhRaw = 18.697375 + 0.0657098244 * n + 24 * fracN
    // 18.697375 ist der Ausgangswert der Greenwicher Sternzeit am 1.1.2000 um 12:00 UTC
    // 0.0657098244 * n berücksichtigt, dass sich die Sternzeit jeden Tag um ca. 0.0657 Stunden verschiebt
    // 24 * fracN rechnet den bereits vergangenen Tagesanteil in Stunden um Beispiel: 24 * 0.25 = 6h

    let thetaGh = thetaGhRaw - 24 * floor(thetaGhRaw / 24)
    // bringt die Sternzeit wieder in den Bereich von 0 bis unter 24 Stunden Beispiel: aus 26.5h wird 2.5h

    let thetaG = thetaGh * 15
    // eine Stunde entspricht 15 Grad, da 360 / 24 = 15
    // dadurch wird die Greenwicher Sternzeit von Stunden in Grad umgerechnet

    let theta = thetaG + longitude
    // zur Greenwicher Sternzeit wird der geografische Längengrad addiert
    // dadurch erhält man die lokale Sternzeit am eigenen Standort

    let tau = theta - alpha
    // Stundenwinkel der Sonne zeigt, wie weit die Sonne östlich oder westlich vom lokalen Meridian steht
    // alpha = Position der Sonne entlang des Himmelsäquators
    // theta = Position, auf die unser lokaler Meridian gerade zeigt
    // tau = Unterschied zwischen theta und alpha

    let h = radToDeg(asin(cos(degToRad(delta)) * cos(degToRad(tau)) * cos(degToRad(latitude))
                          + sin(degToRad(delta)) * sin(degToRad(latitude))))

    // h gibt an, wie viele Grad die Sonne über oder unter dem Horizont steht
    // h > 0  --> Sonne über dem Horizont
    // h = 0  --> Sonnenmittelpunkt am Horizont
    // h < 0  --> Sonne unter dem Horizont
    return (h, tau, delta)
}

func refraktionsHoehe(at date: Date, latitude: Double, longitude: Double) -> Double {

    let h = solarHeight(at: date, latitude: latitude, longitude: longitude).h
    // h = Höhe der Sonne über Horizont in Grad

    let refraktion = 1.02 / tan(degToRad(h + 10.3 / (h + 5.11)))
    // refraktion = atmosphärische Refraktion in Bogenminuten (Formel nach Sæmundsson)
    // die Atmosphäre lässt die Sonne höher erscheinen

    let hR = h + refraktion / 60
    // durch / 60 werden Bogenminuten in Grad umgerechnet
    // hR = scheinbare Höhe des Sonnenmittelpunkts

    return hR
}

// MARK: - Sonnenaufgang, Sonnenuntergang und Sonnenhöchststand

func sonnenaufgang(at date: Date, latitude: Double, longitude: Double) -> Date? {
    // ? bedeutet, dass man nicht sicher ist, ob es einen Wert gibt
    // falls ja, nimmt man ihn, es kann aber auch sein, dass er leer (nil) ist
    let kalender = Calendar.current
    let tagesanfang = kalender.startOfDay(for: date)
    let tagesende = kalender.date(byAdding: .day, value: 1, to: tagesanfang)!
    // mit ! signalisiert man, dass man weiss, dass es dort einen Wert geben muss

    let zielHoehe = -0.2667
    // -0.2667 Grad = Sonnenradius, der obere Rand der Sonne berührt dann den Horizont

    var zeit = tagesanfang
    var vorherigeZeit: Date?
    var vorherigeHoehe: Double?

    while zeit < tagesende {

        let h = solarHeight(at: zeit, latitude: latitude, longitude: longitude).h

        if h > -5 && h < 5 {

            let hR = refraktionsHoehe(at: zeit, latitude: latitude, longitude: longitude)

            // sucht nur die aufsteigende Kreuzung
            // also den Sonnenaufgang und nicht den Sonnenuntergang
            if let letzteHoehe = vorherigeHoehe,
               let letzteZeit = vorherigeZeit,
               letzteHoehe < zielHoehe && hR >= zielHoehe {

                var unten = letzteZeit
                var oben = zeit

                // Binärsuche
                for _ in 0..<12 {

                    let mitte = Date(timeIntervalSince1970:
                        (unten.timeIntervalSince1970 + oben.timeIntervalSince1970) / 2)

                    let hoeheMitte = refraktionsHoehe(at: mitte, latitude: latitude, longitude: longitude)

                    if hoeheMitte < zielHoehe {
                        unten = mitte
                    } else {
                        oben = mitte
                    }
                }

                return oben
            }

            vorherigeZeit = zeit
            vorherigeHoehe = hR
        }

        // geht jeweils 2 Minuten weiter
        zeit = zeit.addingTimeInterval(120)
    }

    return nil
}

func sonnenuntergang(at date: Date, latitude: Double, longitude: Double) -> Date? {

    let kalender = Calendar.current
    let tagesanfang = kalender.startOfDay(for: date)
    let tagesende = kalender.date(byAdding: .day, value: 1, to: tagesanfang)!
    // ! verfestigt den optionalen Wert
    // man sagt Swift damit, dass man sicher ist, dass kein nil vorkommt

    let zielHoehe = -0.2667

    var zeit = tagesanfang
    var vorherigeZeit: Date?
    var vorherigeHoehe: Double?

    while zeit < tagesende {

        let h = solarHeight(at: zeit, latitude: latitude, longitude: longitude).h

        if h > -5 && h < 5 {

            let hR = refraktionsHoehe(at: zeit, latitude: latitude, longitude: longitude)

            // sucht nur die absteigende Kreuzung
            // also den Sonnenuntergang und nicht den Sonnenaufgang
            if let letzteHoehe = vorherigeHoehe,
               let letzteZeit = vorherigeZeit,
               letzteHoehe > zielHoehe && hR <= zielHoehe {

                var unten = letzteZeit
                var oben = zeit

                // wieder Binärsuche
                for _ in 0..<12 {

                    let mitte = Date(timeIntervalSince1970:
                        (unten.timeIntervalSince1970 + oben.timeIntervalSince1970) / 2)

                    let hoeheMitte = refraktionsHoehe(at: mitte, latitude: latitude, longitude: longitude)

                    if hoeheMitte > zielHoehe {
                        unten = mitte
                    } else {
                        oben = mitte
                    }
                }

                return oben
            }

            vorherigeZeit = zeit
            vorherigeHoehe = hR
        }

        // geht 2 Minuten weiter
        zeit = zeit.addingTimeInterval(120)
    }

    return nil
}

func sonnenHoechststand(at date: Date, latitude: Double, longitude: Double) -> Date? {
    // Sonnenhöchststand (Mittag) = Zeitpunkt, an dem die Sonne genau im Süden steht
    // dann ist der Stundenwinkel tau = 0
    // vorher ist tau negativ (Sonne im Osten), danach positiv (Sonne im Westen)
    // das funktioniert auch an Tagen, an denen die Sonne gar nicht aufgeht

    let kalender = Calendar.current
    let tagesanfang = kalender.startOfDay(for: date)
    let tagesende = kalender.date(byAdding: .day, value: 1, to: tagesanfang)!

    var zeit = tagesanfang
    var vorherigeZeit: Date?
    var vorherigerTau: Double?

    while zeit < tagesende {

        let tau = normalisiereWinkel(solarHeight(at: zeit, latitude: latitude, longitude: longitude).tau)

        // sucht den Wechsel von negativ zu positiv
        if let letzterTau = vorherigerTau,
           let letzteZeit = vorherigeZeit,
           letzterTau < 0 && tau >= 0 {

            var unten = letzteZeit
            var oben = zeit

            // Binärsuche wie beim Sonnenaufgang, nur mit tau statt mit der Höhe
            for _ in 0..<12 {

                let mitte = Date(timeIntervalSince1970:
                    (unten.timeIntervalSince1970 + oben.timeIntervalSince1970) / 2)

                let tauMitte = normalisiereWinkel(solarHeight(at: mitte, latitude: latitude, longitude: longitude).tau)

                if tauMitte < 0 {
                    unten = mitte
                } else {
                    oben = mitte
                }
            }

            return oben
        }

        vorherigeZeit = zeit
        vorherigerTau = tau

        zeit = zeit.addingTimeInterval(120)
    }

    return nil
}

func sonnenzeiten(at date: Date, latitude: Double, longitude: Double) -> (aufgang: Date, untergang: Date, mittag: Date)? {
    // gibt Sonnenaufgang, Sonnenuntergang und Mittag zurück
    // dabei wird die 5-Stunden-Regel angewendet:
    // Tag und Nacht dürfen nie kürzer als 5 Stunden sein
    // ist der Tag oder die Nacht kürzer, werden Aufgang und Untergang so verschoben,
    // dass genau 5 Stunden übrig bleiben (je 2.5 Stunden um die Mitte herum)

    guard let mittag = sonnenHoechststand(at: date, latitude: latitude, longitude: longitude)
    else { return nil }

    var aufgang = sonnenaufgang(at: date, latitude: latitude, longitude: longitude)
    var untergang = sonnenuntergang(at: date, latitude: latitude, longitude: longitude)

    let hoeheMittag = refraktionsHoehe(at: mittag, latitude: latitude, longitude: longitude)
    // wie hoch die Sonne am Mittag steht

    let halbeMinimaleDauer = minimaleDauer / 2
    // 2.5 Stunden

    let halberTag: TimeInterval = 12 * 3600
    // Mitternacht liegt ungefähr 12 Stunden vor bzw. nach dem Mittag

    // 1. Ist der Tag zu kurz?
    var tagZuKurz = false

    if let a = aufgang, let u = untergang {
        if u.timeIntervalSince(a) < minimaleDauer {
            tagZuKurz = true
        }
    } else if hoeheMittag < -0.2667 {
        // die Sonne geht den ganzen Tag nicht auf (Polarnacht)
        tagZuKurz = true
    }

    if tagZuKurz {
        aufgang = mittag.addingTimeInterval(-halbeMinimaleDauer)
        untergang = mittag.addingTimeInterval(halbeMinimaleDauer)
    } else {

        // 2. Ist die Nacht vor diesem Tag zu kurz?
        let untergangGestern = sonnenuntergang(at: tagVerschieben(date, um: -1), latitude: latitude, longitude: longitude)

        if let a = aufgang, let ug = untergangGestern {
            if a.timeIntervalSince(ug) < minimaleDauer {
                aufgang = mittag.addingTimeInterval(-halberTag + halbeMinimaleDauer)
                // Mitternacht + 2.5 Stunden
            }
        } else {
            // kein Aufgang oder kein Untergang gestern --> die Sonne geht nicht unter (Mitternachtssonne)
            aufgang = mittag.addingTimeInterval(-halberTag + halbeMinimaleDauer)
        }

        // 3. Ist die Nacht nach diesem Tag zu kurz?
        let aufgangMorgen = sonnenaufgang(at: tagVerschieben(date, um: 1), latitude: latitude, longitude: longitude)

        if let u = untergang, let am = aufgangMorgen {
            if am.timeIntervalSince(u) < minimaleDauer {
                untergang = mittag.addingTimeInterval(halberTag - halbeMinimaleDauer)
                // nächste Mitternacht - 2.5 Stunden
            }
        } else {
            untergang = mittag.addingTimeInterval(halberTag - halbeMinimaleDauer)
        }
    }

    guard let a = aufgang, let u = untergang
    else { return nil }

    return (a, u, mittag)
}

// MARK: - Hilfsfunktionen

func tagVerschieben(_ date: Date, um tage: Int) -> Date {
    // verschiebt ein Datum um eine bestimmte Anzahl Tage
    // besser als +86400 Sekunden, weil ein Tag bei der Zeitumstellung 23 oder 25 Stunden hat
    return Calendar.current.date(byAdding: .day, value: tage, to: date)!
}

func normalisiereWinkel(_ winkel: Double) -> Double {
    // bringt einen Winkel in den Bereich von -180 bis 180 Grad
    // Beispiel: aus 350° wird -10°, aus 370° wird 10°

    var w = winkel - 360 * floor(winkel / 360)
    // zuerst in den Bereich 0 bis unter 360 Grad (gleiche Idee wie bei der Sternzeit)

    if w > 180 {
        w = w - 360
    }

    return w
}

func nachtLaenge(at date: Date, latitude: Double, longitude: Double) -> TimeInterval? {
    // Nacht = vom Sonnenuntergang des Vortags bis zum Sonnenaufgang dieses Tags

    guard let heute = sonnenzeiten(at: date, latitude: latitude, longitude: longitude),
          let gestern = sonnenzeiten(at: tagVerschieben(date, um: -1), latitude: latitude, longitude: longitude)
    else { return nil }

    return heute.aufgang.timeIntervalSince(gestern.untergang)
}

func sucheSonnenHoeheZwischen(von start: Date, bis ende: Date, latitude: Double, longitude: Double, zielHoehe: Double, aufsteigend: Bool) -> Date? {
    // sucht den Zeitpunkt zwischen start und ende, an dem die Sonne eine bestimmte Höhe erreicht
    // aufsteigend = true  --> morgens (Sonne steigt)
    // aufsteigend = false --> abends (Sonne sinkt)
    // so kann man auch über Mitternacht hinaus suchen (z. B. Isha im Sommer)

    var zeit = start
    var vorherigeZeit: Date?
    var vorherigeHoehe: Double?

    while zeit <= ende {

        let h = solarHeight(at: zeit, latitude: latitude, longitude: longitude).h

        if let letzteHoehe = vorherigeHoehe,
           let letzteZeit = vorherigeZeit,
           ((aufsteigend && letzteHoehe < zielHoehe && h >= zielHoehe) ||
            (!aufsteigend && letzteHoehe > zielHoehe && h <= zielHoehe)) {

            var unten = letzteZeit
            var oben = zeit

            for _ in 0..<12 {

                let mitte = Date(timeIntervalSince1970:
                    (unten.timeIntervalSince1970 + oben.timeIntervalSince1970) / 2)

                let hoeheMitte = solarHeight(at: mitte, latitude: latitude, longitude: longitude).h

                // steigt die Sonne, liegt der Zeitpunkt später, wenn sie noch unter dem Ziel ist
                // sinkt die Sonne, ist es genau umgekehrt
                let unterZiel = hoeheMitte < zielHoehe

                if unterZiel == aufsteigend {
                    unten = mitte
                } else {
                    oben = mitte
                }
            }

            return oben
        }

        vorherigeZeit = zeit
        vorherigeHoehe = h

        zeit = zeit.addingTimeInterval(120)
    }

    return nil
}

func sucheSonnenHoehe(at date: Date, latitude: Double, longitude: Double, zielHoehe: Double, aufsteigend: Bool) -> Date? {
    // gleiche Suche wie oben, aber über einen ganzen Kalendertag

    let kalender = Calendar.current
    let tagesanfang = kalender.startOfDay(for: date)
    let tagesende = kalender.date(byAdding: .day, value: 1, to: tagesanfang)!

    return sucheSonnenHoeheZwischen(von: tagesanfang, bis: tagesende, latitude: latitude, longitude: longitude,
                                    zielHoehe: zielHoehe, aufsteigend: aufsteigend)
}

// MARK: - Tatsächlicher Fajr und tatsächliche Isha

func tatsaechlicherFajr(at date: Date, latitude: Double, longitude: Double) -> Date? {
    // Zeitpunkt, an dem die Sonne vor dem Sonnenaufgang 18 Grad unter dem Horizont ist
    // gesucht wird vom Sonnenuntergang gestern bis zum Sonnenaufgang heute

    guard let heute = sonnenzeiten(at: date, latitude: latitude, longitude: longitude),
          let gestern = sonnenzeiten(at: tagVerschieben(date, um: -1), latitude: latitude, longitude: longitude)
    else { return nil }

    return sucheSonnenHoeheZwischen(von: gestern.untergang, bis: heute.aufgang, latitude: latitude, longitude: longitude,
                                    zielHoehe: -18, aufsteigend: true)
}

func tatsaechlicheIsha(at date: Date, latitude: Double, longitude: Double) -> Date? {
    // Zeitpunkt, an dem die Sonne nach dem Sonnenuntergang 16 Grad unter dem Horizont ist
    // gesucht wird vom Sonnenuntergang heute bis zum Sonnenaufgang morgen

    guard let heute = sonnenzeiten(at: date, latitude: latitude, longitude: longitude),
          let morgen = sonnenzeiten(at: tagVerschieben(date, um: 1), latitude: latitude, longitude: longitude)
    else { return nil }

    return sucheSonnenHoeheZwischen(von: heute.untergang, bis: morgen.aufgang, latitude: latitude, longitude: longitude,
                                    zielHoehe: -16, aufsteigend: false)
}

func fajrGanzesJahr(at date: Date, latitude: Double, longitude: Double) -> Bool {
    // prüft, ob es den tatsächlichen Fajr das ganze Jahr gibt
    // am 21. Juni ist die Nacht am kürzesten
    // gibt es an diesem Tag einen Fajr, dann gibt es ihn an jedem Tag des Jahres
    // (gilt für die ganze Schweiz)

    return tatsaechlicherFajr(at: einundzwanzigsterJuni(at: date), latitude: latitude, longitude: longitude) != nil
}

func einundzwanzigsterJuni(at date: Date) -> Date {
    // gibt den 21. Juni des gleichen Jahres zurück (um 12 Uhr)

    let kalender = Calendar.current
    let jahr = kalender.component(.year, from: date)

    return kalender.date(from: DateComponents(year: jahr, month: 6, day: 21, hour: 12))!
}

// MARK: - Ersatzregel, wenn es keinen tatsächlichen Fajr gibt

func verhaeltnisLetzterFajr(at date: Date, latitude: Double, longitude: Double) -> (fajrAnteil: Double, ishaAnteil: Double)? {
    // In Zeiten ohne tatsächlichen Fajr (nur weit im Norden, nicht in der Schweiz)
    // wird der letzte Tag gesucht, an dem es noch einen tatsächlichen Fajr gab.
    // Für diesen Tag wird berechnet, welchen Anteil der Nacht Fajr und Isha hatten.
    // Dieser Anteil wird dann auf die Nacht des heutigen Tags angewendet.
    // ACHTUNG: Das Dokument ist hier ungenau formuliert, das ist unsere Interpretation:
    // Isha mit -16 Grad, Fajr mit "2 Grad Unterschied", also -18 Grad

    for tage in 1...366 {
        // geht Tag für Tag zurück, bis es wieder einen tatsächlichen Fajr gibt

        let tag = tagVerschieben(date, um: -tage)

        if let echterFajr = tatsaechlicherFajr(at: tag, latitude: latitude, longitude: longitude),
           let echteIsha = tatsaechlicheIsha(at: tag, latitude: latitude, longitude: longitude),
           let heute = sonnenzeiten(at: tag, latitude: latitude, longitude: longitude),
           let gestern = sonnenzeiten(at: tagVerschieben(tag, um: -1), latitude: latitude, longitude: longitude),
           let morgen = sonnenzeiten(at: tagVerschieben(tag, um: 1), latitude: latitude, longitude: longitude) {

            let nachtVorher = heute.aufgang.timeIntervalSince(gestern.untergang)
            let nachtNachher = morgen.aufgang.timeIntervalSince(heute.untergang)

            let fajrAnteil = heute.aufgang.timeIntervalSince(echterFajr) / nachtVorher
            // welcher Teil der Nacht liegt zwischen Fajr und Sonnenaufgang
            // Beispiel: 0.25 bedeutet, Fajr ist ein Viertel der Nacht vor dem Sonnenaufgang

            let ishaAnteil = echteIsha.timeIntervalSince(heute.untergang) / nachtNachher
            // welcher Teil der Nacht liegt zwischen Maghrib und Isha

            return (fajrAnteil, ishaAnteil)
        }
    }

    return nil
}

// MARK: - Gebetszeiten

// MARK: - Fajr/Isha nach dem Kongressverfahren (Mihrab-Port)
// Die frühere unbestätigte smoothstep-Übergangsfunktion wurde entfernt.
// Die Berechnung von Fajr und Isha folgt ab hier dem unabhängig geprüften
// Kalender- und Sommeralgorithmus am Dateiende (MPL-2.0).

func fajr(at date: Date, latitude: Double, longitude: Double) -> Date? {
    mihrabKongressFajrIsha(at: date, latitude: latitude, longitude: longitude).fajr
}

func isha(at date: Date, latitude: Double, longitude: Double) -> Date? {
    mihrabKongressFajrIsha(at: date, latitude: latitude, longitude: longitude).isha
}

func asr(at date: Date, latitude: Double, longitude: Double) -> Date? {
    // Asr = wenn der Schatten eines Gegenstands so lang ist wie der Gegenstand selbst
    // plus der Schatten, den er am Mittag hat
    // gibt nil zurück, wenn es kein Asr-Zeichen gibt (dann gilt Asr = Dhuhr)

    guard let mittag = sonnenHoechststand(at: date, latitude: latitude, longitude: longitude)
    else { return nil }

    let delta = solarHeight(at: mittag, latitude: latitude, longitude: longitude).delta
    // Deklination der Sonne am Mittag

    let mittagsSchatten = tan(degToRad(abs(latitude - delta)))
    // Schattenlänge am Mittag für einen Gegenstand mit Länge 1
    // am Mittag steht die Sonne 90 - |latitude - delta| Grad hoch

    let zielHoehe = radToDeg(atan(1 / (1 + mittagsSchatten)))
    // die Sonne muss so tief stehen, dass der Schatten 1 + mittagsSchatten lang ist
    // Beispiel: mittagsSchatten = 0.5 --> Schatten 1.5 --> Höhe = atan(1 / 1.5) = 33.7 Grad

    let tagesende = tagVerschieben(Calendar.current.startOfDay(for: date), um: 1)

    return sucheSonnenHoeheZwischen(von: mittag, bis: tagesende, latitude: latitude, longitude: longitude,
                                    zielHoehe: zielHoehe, aufsteigend: false)
}

// MARK: - Alle Gebetszeiten zusammen

struct Gebetszeiten {
    // struct = eigener Datentyp, der mehrere Werte zusammenfasst
    let fajr: Date
    let sonnenaufgang: Date
    let dhuhr: Date
    let asr: Date
    let maghrib: Date
    let isha: Date
}

func berechneGebetszeiten(at date: Date, latitude: Double, longitude: Double) -> Gebetszeiten? {
    // berechnet alle Zeiten eines Tags und rechnet am Schluss die Tamkin-Minuten dazu

    guard let sonne = sonnenzeiten(at: date, latitude: latitude, longitude: longitude)
    else { return nil }
    let neueSommerzeiten = mihrabKongressFajrIsha(at: date, latitude: latitude, longitude: longitude)
    let fajrZeit = neueSommerzeiten.fajr
    let ishaZeit = neueSommerzeiten.isha

    let dhuhrZeit = sonne.mittag.addingTimeInterval(tamkinDhuhr)

    // wenn es kein Asr-Zeichen gibt, gilt Asr = Dhuhr
    var asrZeit = dhuhrZeit

    if let echterAsr = asr(at: date, latitude: latitude, longitude: longitude) {
        asrZeit = echterAsr.addingTimeInterval(tamkinAsr)
    }

    return Gebetszeiten(
        fajr: fajrZeit.addingTimeInterval(tamkinFajr),
        sonnenaufgang: sonne.aufgang.addingTimeInterval(tamkinSonnenaufgang),
        dhuhr: dhuhrZeit,
        asr: asrZeit,
        maghrib: sonne.untergang.addingTimeInterval(tamkinMaghrib),
        isha: ishaZeit.addingTimeInterval(tamkinIsha)
    )
}

// MARK: - Wissenschaftliche Diagnostik
// Ausgaben getrennt von der eigentlichen Gebetszeitliste.
func fidsDebugAusgabe(at date: Date, latitude: Double, longitude: Double) -> String {
    let port = mihrabKongressFajrIsha(at: date, latitude: latitude, longitude: longitude)
    let fmt = ISO8601DateFormatter()
    fmt.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
    fmt.formatOptions = [.withInternetDateTime]
    return "Mihrab-Kongress-Port: Fajr=\(fmt.string(from: port.fajr)); Isha=\(fmt.string(from: port.isha))"
}

// MARK: - Umrechnung

func degToRad(_ degrees: Double) -> Double {
    return degrees * Double.pi / 180
}

func radToDeg(_ radians: Double) -> Double {
    return radians * 180 / Double.pi
}

// BEGINN MIHRAB-KONGRESS-PORT
// SPDX-License-Identifier: MPL-2.0
// Port der Kernlogik aus Mihrab Methods, methods/sweden.js (vom Nutzer
// am 22.11.2026 bereitgestelltes npm-Paket). Urheber: MihrabHQ.
// Ableitung nach MPL-2.0; Änderungen: Swift-Port und Date-Datentyp.
// Original: https://github.com/MihrabHQ/mihrab-methods
// Die bestehenden Sonnenzeiten/Asr-Berechnungen dieser App bleiben unabhängig.

private let mkRAD = Double.pi / 180
private let mkDay: Double = 86400
private let mkFajrAlt = -18.0
private let mkIshaAlt = -16.0
private let mkFloor = 300.0
private let mkBand = 20.0
private let mkSunInstant = -45.0
private let mkEotAdd = 0.00176

private func mkDayKey(_ year: Int, _ monthZero: Int, _ day: Int) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let first = calendar.date(from: DateComponents(year: year, month: monthZero + 1, day: day))!
    return Int(floor(first.timeIntervalSince1970 / mkDay))
}
private func mkMid(_ year: Int) -> Int { mkDayKey(year, 5, 21) }
private func mkInstant(_ day: Int, _ minutes: Double) -> Date {
    Date(timeIntervalSince1970: floor((Double(day) * 1440 + minutes) + 0.5) * 60)
}
private func mkModulo360(_ a: Double) -> Double { (a.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }

private struct MKSolar {
    let lat: Double
    let dec: Double // radians
    let transit: Double // minutes from 0 UTC
    init(day: Int, lat: Double, lon: Double) {
        self.lat = lat
        let utcMs = Double(day) * mkDay * 1000 + mkSunInstant * 1000
        let T = (utcMs / (mkDay * 1000) - 10957.5) / 36525
        let L0 = mkModulo360(280.46646 + T * (36000.76983 + 0.0003032 * T))
        let M = (357.52911 + T * (35999.05029 - 0.0001537 * T)) * mkRAD
        let C = (1.914602 - T * (0.004817 + 0.000014 * T)) * sin(M) + (0.019993 - 0.000101 * T) * sin(2 * M) + 0.000289 * sin(3 * M)
        let om = (125.04 - 1934.136 * T) * mkRAD
        let Ls = (280.4665 + 36000.7698 * T) * mkRAD
        let Lm = (218.3165 + 481267.8813 * T) * mkRAD
        let eps = 23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60 + (9.2 * cos(om) + 0.57 * cos(2 * Ls) + 0.1 * cos(2 * Lm) - 0.09 * cos(2 * om)) / 3600
        let lam = (L0 + C) * mkRAD
        let ra = mkModulo360(atan2(cos(eps * mkRAD) * sin(lam), cos(lam)) / mkRAD)
        let L = L0 * mkRAD
        let residualDec = -1.1539e-5 - 3.6174e-5 * sin(L) - 2.1101e-5 * cos(L) + 2.0235e-5 * sin(2 * L) - 2.2534e-5 * cos(2 * L)
        dec = asin(sin(eps * mkRAD) * sin(lam)) + residualDec * mkRAD
        let residualEot = 0.033377 * sin(L) + 0.007721 * cos(L) - 0.000229 * sin(2 * L) + 0.004198 * cos(2 * L) - 0.02346 * sin(3 * L) - 0.026434 * cos(3 * L)
        let eot = (mkModulo360(L0 - ra + 180) - 180) * 4 + mkEotAdd - residualEot / 60
        transit = 720 - 4 * lon - eot
    }
    func hourAngle(_ alt: Double) -> Double? {
        let c = (sin(alt * mkRAD) - sin(lat * mkRAD) * sin(dec)) / (cos(lat * mkRAD) * cos(dec))
        guard c >= -1, c <= 1 else { return nil }
        return acos(c) / mkRAD * 4
    }
    func rising(_ alt: Double) -> Double? { hourAngle(alt).map { transit - $0 } }
    func setting(_ alt: Double) -> Double? { hourAngle(alt).map { transit + $0 } }
}

private struct MKRiseSet { let sr: Double; let ss: Double; let held: Bool }
private struct MKRamp { let edge: Int; let T: Double; let far: Int?; let bump: Bool }

private final class MKCongressYear {
    let lat: Double
    let lon: Double
    let year: Int
    private var solars: [Int: MKSolar] = [:]
    private var sets: [Int: MKRiseSet] = [:]
    private var cachedRatio: Double? = nil
    private var ratioReady = false
    private var cachedGap: (Int, Int)? = nil
    private var gapReady = false
    private var floorCache: Bool? = nil
    private var extremeCache: [Int: (Double,Double)] = [:]
    private var carriedCache: [Int: (Double,Double)] = [:]
    private var ramps: [String: MKRamp] = [:]

    init(_ latitude: Double, _ longitude: Double, _ year: Int) {
        lat = latitude; lon = longitude; self.year = year
    }
    private func solar(_ day: Int) -> MKSolar {
        if let v = solars[day] { return v }
        let v = MKSolar(day: day, lat: lat, lon: lon)
        solars[day] = v
        return v
    }
    private func dhuhr(_ day: Int) -> Double { solar(day).transit + 5 }
    private func maghribFloored(_ day: Int) -> Bool {
        let s = solar(day)
        guard let ss = s.setting(-0.833) else { return true }
        return ss + 7 > s.transit + 5 + 720 - mkFloor / 2
    }
    private func floorAtMidsummer() -> Bool {
        if let v = floorCache { return v }
        let s = solar(mkMid(year))
        var v = true
        if let sr = s.rising(-0.833), let ss = s.setting(-0.833) {
            let pSr = max(sr - 7, s.transit + 5 - 720 + mkFloor / 2)
            let pSs = min(ss + 7, s.transit + 5 + 720 - mkFloor / 2)
            v = 1440 - (pSs - pSr) <= mkFloor + 1
        }
        floorCache = v
        return v
    }
    private func extrema(_ day: Int) -> (Double, Double) {
        if let e = extremeCache[day] { return e }
        let mid = mkMid(year)
        let out: (Double,Double)
        if day <= mid {
            var maxRun = dhuhr(day)
            if maghribFloored(day) {
                var d = day - 1
                while d > day - 120 && maghribFloored(d) {
                    maxRun = max(maxRun,dhuhr(d))
                    d -= 1
                }
            }
            out = (max(dhuhr(day), dhuhr(mid)), min(maxRun,dhuhr(mid)))
        } else {
            var hi = -Double.infinity; var lo = Double.infinity
            for d in mid...day {
                let v = dhuhr(d); hi = max(hi,v); lo = min(lo,v)
            }
            out = (hi,lo)
        }
        extremeCache[day] = out
        return out
    }
    private func riseSet(_ day: Int) -> MKRiseSet {
        if let v = sets[day] { return v }
        let s = solar(day); let noon = s.transit + 5
        let nSr: Double; let nSs: Double
        if floorAtMidsummer() {
            let (hi,lo) = extrema(day)
            nSr = hi - 720 + mkFloor / 2
            nSs = lo + 720 - mkFloor / 2
        } else {
            nSr = noon - 720 + mkFloor / 2
            nSs = noon + 720 - mkFloor / 2
        }
        var sr: Double; var ss: Double
        if let rawSr = s.rising(-0.833), let rawSs = s.setting(-0.833) {
            sr = rawSr - 7; ss = rawSs + 7
        } else {
            let noonUp = 90 - abs(lat - s.dec / mkRAD) > -0.833
            sr = noonUp ? nSr : noon - mkFloor/2
            ss = noonUp ? nSs : noon + mkFloor/2
        }
        sr = max(min(sr, noon - mkFloor/2),nSr)
        ss = min(max(ss, noon + mkFloor/2),nSs)
        var held = false
        if floorAtMidsummer() {
            let mid = mkMid(year)
            if day == mid { held = true }
            else if day > mid {
                let prev = riseSet(day - 1)
                if prev.held && ss > prev.ss { ss = prev.ss; held = true }
            }
        }
        let result = MKRiseSet(sr: sr,ss: ss,held: held)
        sets[day] = result
        return result
    }
    private func night(_ day: Int) -> Double {
        let rs = riseSet(day)
        return 1440 - (rs.ss - rs.sr)
    }
    private func trueTime(_ key: String, _ day: Int) -> Double? {
        key == "fajr" ? solar(day).rising(-18) : solar(day).setting(-16)
    }
    private func ratio() -> Double? {
        if ratioReady { return cachedRatio }
        ratioReady = true
        var d = mkMid(year); var f = trueTime("fajr",d); var steps = 0
        while f == nil && steps < 200 { d -= 1; f = trueTime("fajr",d); steps += 1 }
        guard let fajr = f else { return nil }
        let ss = riseSet(d).ss
        let shariaNight = fajr + 1440 - ss
        cachedRatio = shariaNight / 3 / night(d)
        return cachedRatio
    }
    private func carriedRaw(_ day: Int) -> (Double,Double) {
        let r = ratio() ?? 0
        let rs = riseSet(day)
        let n = night(day)
        return (rs.sr - r * (18.0 / 16.0) * n, rs.ss + r * n)
    }
    private func carried(_ day: Int) -> (Double, Double) {
        if let v = carriedCache[day] { return v }
        let mid = mkMid(year)
        let out: (Double,Double)
        if !floorAtMidsummer() || day == mid {
            out = carriedRaw(day)
        } else if day < mid {
            let (f,i) = carriedRaw(day)
            let (mf,mi) = carried(mid)
            out = (max(f,mf),min(i,mi))
        } else {
            var prev = carried(mid)
            if day > mid + 1 {
                for d in (mid + 1)..<day {
                    if let c = carriedCache[d] { prev = c }
                    else {
                        let (f,i) = carriedRaw(d)
                        let c = (max(f,prev.0),min(i,prev.1))
                        carriedCache[d] = c
                        prev = c
                    }
                }
            }
            let (f,i) = carriedRaw(day)
            out = (max(f,prev.0),min(i,prev.1))
        }
        carriedCache[day] = out
        return out
    }
    private func gapDays() -> (Int,Int)? {
        if gapReady { return cachedGap }
        gapReady = true
        let mid = mkMid(year)
        if trueTime("fajr",mid) != nil {
            if lat > 0, let i = solar(mid).setting(-16), carriedRaw(mid).1 < i {
                cachedGap = (mid,mid)
            }
            return cachedGap
        }
        var a = mid; var b = mid
        while a > mid - 200 && trueTime("fajr",a - 1) == nil { a -= 1 }
        while b < mid + 200 && trueTime("fajr",b + 1) == nil { b += 1 }
        cachedGap = (a,b)
        return cachedGap
    }
    private func ramp(_ day: Int, _ side: String, _ key: String) -> Double? {
        guard let gap = gapDays() else { return trueTime(key,day) }
        let edge = side == "in" ? gap.0 : gap.1
        let cacheKey = side + key
        if ramps[cacheKey] == nil {
            let T = key == "fajr" ? carried(edge).0 : carried(edge).1
            let step = side == "in" ? -1 : 1
            var far: Int? = nil
            var d = edge + step
            while abs(d - edge) < 200 {
                if let t = trueTime(key,d), abs(t - T) <= mkBand { far = d }
                else if far != nil { break }
                d += step
            }
            // Schweizer Zeitzone: Der seltene Sonderfall bei Ortszeiten östlich
            // ihrer Zonenmitte (Aihui) tritt nicht auf.
            ramps[cacheKey] = MKRamp(edge:edge,T:T,far:far,bump:false)
        }
        let r = ramps[cacheKey]!
        guard let far = r.far else { return trueTime(key,day) }
        let inside = side == "in" ? (far <= day && day < edge) : (edge < day && day <= far)
        guard inside else { return trueTime(key,day) }
        let sign = key == "fajr" ? 1.0 : -1.0
        return r.T + sign * mkBand * Double(abs(day-edge)) / Double(abs(far-edge))
    }
    func times(_ day: Int) -> (fajr: Date, isha: Date) {
        var f = trueTime("fajr",day)
        var i = trueTime("isha",day)
        if let gap = gapDays() {
            if gap.0 <= day && day <= gap.1 {
                let c = carried(day)
                f = c.0; i = c.1
                if day == gap.0 || day == gap.1 {
                    let side = day == gap.0 ? "in" : "out"
                    _ = ramp(day,side,"fajr")
                    _ = ramp(day,side,"isha")
                    if ramps[side+"fajr"]?.bump == true { f = (f ?? 0) + mkBand }
                    if ramps[side+"isha"]?.bump == true { i = (i ?? 0) - mkBand }
                }
            } else if day < gap.0 {
                f = ramp(day,"in","fajr")
                i = ramp(day,"in","isha")
            } else {
                f = ramp(day,"out","fajr")
                i = ramp(day,"out","isha")
            }
        }
        let rs = riseSet(day)
        return (mkInstant(day, f ?? rs.sr - 60), mkInstant(day, i ?? rs.ss + 60))
    }
}

private func mihrabKongressFajrIsha(at date: Date, latitude: Double, longitude: Double) -> (fajr: Date, isha: Date) {
    var local = Calendar(identifier: .gregorian)
    local.timeZone = TimeZone(identifier:"Europe/Zurich")!
    let c = local.dateComponents([.year,.month,.day], from: date)
    let year = c.year!
    let day = mkDayKey(year,(c.month ?? 1)-1,c.day ?? 1)
    return MKCongressYear(latitude,longitude,year).times(day)
}
// ENDE MIHRAB-KONGRESS-PORT

