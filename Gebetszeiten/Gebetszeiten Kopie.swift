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

    let JD = unixSeconds / 86400.0 + 2440587.55

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

func fajr(at date: Date, latitude: Double, longitude: Double) -> Date? {

    guard let heute = sonnenzeiten(at: date, latitude: latitude, longitude: longitude),
          let nacht = nachtLaenge(at: date, latitude: latitude, longitude: longitude)
    else { return nil }

    // 1. echter Fajr:
    // wenn es ihn gibt, der Zeitpunkt bei -18 Grad
    // sonst die Ersatzregel mit dem Verhältnis vom letzten Tag mit Fajr
    let echterFajr: Date

    if let tatsaechlich = tatsaechlicherFajr(at: date, latitude: latitude, longitude: longitude) {
        echterFajr = tatsaechlich
    } else if let verhaeltnis = verhaeltnisLetzterFajr(at: date, latitude: latitude, longitude: longitude) {
        echterFajr = heute.aufgang.addingTimeInterval(-verhaeltnis.fajrAnteil * nacht)
    } else {
        echterFajr = heute.aufgang.addingTimeInterval(-(11.0 / 24.0) * nacht)
    }

    // 2. unterhalb von 44.5 Grad gelten nur die echten Zeiten
    if abs(latitude) < breitengradGrenze {
        return echterFajr
    }

    // 3. bestimmter Fajr:
    // Sonnenaufgang minus (1/3 + 2/16) der Nacht
    // 1/3 + 2/16 = 8/24 + 3/24 = 11/24
    // wenn es das ganze Jahr Fajr gibt, wird die Nacht vom 21. Juni verwendet
    var nachtFuerBestimmung = nacht

    if fajrGanzesJahr(at: date, latitude: latitude, longitude: longitude),
       let nacht21Juni = nachtLaenge(at: einundzwanzigsterJuni(at: date), latitude: latitude, longitude: longitude) {
        nachtFuerBestimmung = nacht21Juni
    }

    let bestimmterFajr = heute.aufgang.addingTimeInterval(-(11.0 / 24.0) * nachtFuerBestimmung + uebergang)
    // + uebergang: der bestimmte Fajr beginnt 20 Minuten später (schrittweiser Übergang)

    // 4. ist der echte Fajr früher als der bestimmte, wird der bestimmte verwendet
    if echterFajr < bestimmterFajr {
        return bestimmterFajr
    } else {
        return echterFajr
    }
}

func isha(at date: Date, latitude: Double, longitude: Double) -> Date? {

    guard let heute = sonnenzeiten(at: date, latitude: latitude, longitude: longitude),
          let morgen = sonnenzeiten(at: tagVerschieben(date, um: 1), latitude: latitude, longitude: longitude)
    else { return nil }

    let maghrib = heute.untergang
    let nacht = morgen.aufgang.timeIntervalSince(maghrib)
    // Nacht = von Maghrib heute bis Sonnenaufgang morgen

    // 1. echte Isha:
    // wenn es sie gibt, der Zeitpunkt bei -16 Grad
    // sonst die Ersatzregel mit dem Verhältnis vom letzten Tag mit Fajr
    let echteIsha: Date

    if let tatsaechlich = tatsaechlicheIsha(at: date, latitude: latitude, longitude: longitude) {
        echteIsha = tatsaechlich
    } else if let verhaeltnis = verhaeltnisLetzterFajr(at: date, latitude: latitude, longitude: longitude) {
        echteIsha = maghrib.addingTimeInterval(verhaeltnis.ishaAnteil * nacht)
    } else {
        echteIsha = maghrib.addingTimeInterval(nacht / 3)
    }

    // 2. unterhalb von 44.5 Grad gelten nur die echten Zeiten
    if abs(latitude) < breitengradGrenze {
        return echteIsha
    }

    // 3. bestimmte Isha:
    // Maghrib + 1/3 der Nacht
    // wenn es das ganze Jahr Fajr gibt, wird die Nacht vom 21. Juni verwendet
    var nachtFuerBestimmung = nacht

    if fajrGanzesJahr(at: date, latitude: latitude, longitude: longitude),
       let nacht21Juni = nachtLaenge(at: tagVerschieben(einundzwanzigsterJuni(at: date), um: 1), latitude: latitude, longitude: longitude) {
        // die Nacht nach dem 21. Juni = Sonnenaufgang am 22. Juni minus Sonnenuntergang am 21. Juni
        nachtFuerBestimmung = nacht21Juni
    }

    let bestimmteIsha = maghrib.addingTimeInterval(nachtFuerBestimmung / 3 - uebergang)
    // - uebergang: die bestimmte Isha beginnt 20 Minuten früher (schrittweiser Übergang)

    // 4. ist die echte Isha später als die bestimmte, wird die bestimmte verwendet
    if echteIsha > bestimmteIsha {
        return bestimmteIsha
    } else {
        return echteIsha
    }
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

    guard let sonne = sonnenzeiten(at: date, latitude: latitude, longitude: longitude),
          let fajrZeit = fajr(at: date, latitude: latitude, longitude: longitude),
          let ishaZeit = isha(at: date, latitude: latitude, longitude: longitude)
    else { return nil }

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

// MARK: - Umrechnung

func degToRad(_ degrees: Double) -> Double {
    return degrees * Double.pi / 180
}

func radToDeg(_ radians: Double) -> Double {
    return radians * 180 / Double.pi
}
