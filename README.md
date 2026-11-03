# Gleich

Eine schlichte Fahrplan-App fürs iPhone. Beim Öffnen zeigt sie sofort, was an der nächsten Haltestelle abfährt – überall in Deutschland.

## Was die App kann

- **Abfahrten in der Nähe:** Oben steht der Name der Haltestelle, darunter Linie, Richtung und Minuten bis zur Abfahrt.
  Linien erscheinen in ihren gewohnten Farben (S-Bahn rund, U-Bahn eckig, Tram rot, Bus lila).
  Eine rote Zeit heißt: Der Zug ist verspätet, angezeigt wird die tatsächliche Abfahrt.
  Blasse Zeilen schafft man zu Fuß wahrscheinlich nicht mehr – mit etwas Glück aber doch.
- **Große Bahnhöfe** gelten als eine Haltestelle. Dann erscheinen oben kleine Symbole für die Verkehrsmittel (S, U, Tram, Bus, Zug); ein Tipp zeigt nur dieses Verkehrsmittel.
- **Wischen nach links** zeigt die nächstgelegene Haltestelle, dann die übernächste.
- **Antippen einer Abfahrt** zeigt die weiteren Halte mit Uhrzeit. **Antippen des Haltestellennamens** öffnet den Fußweg in Apple Karten; langes Drücken bietet „Merken“ an.
- **Suche unten („Wohin?“):** Verbindungen von hier, ab jetzt. Gemerkte Orte („Zuhause“, „Arbeit“ …) stehen ganz oben. Ein Tipp auf eine Verbindung klappt die einzelnen Schritte auf; weiter unten folgen spätere Verbindungen.
- **Aktualisieren:** beim Öffnen und durch Herunterziehen der Liste. Beim Laden tuckert eine kleine Dampflok.
- **Widgets:** für den Home-Bildschirm (drei Abfahrten) und den Sperrbildschirm (zwei Abfahrten).
- Ist die nächste Haltestelle mehr als 5 km entfernt, sagt die App das deutlich.

## Woher die Daten kommen

- [Transitous](https://transitous.org) – ein freier Dienst mit den Fahrplänen aller Verkehrsverbünde in Deutschland (und darüber hinaus), mit Echtzeitdaten, wo die Verkehrsunternehmen sie liefern.
- In Berlin und Brandenburg kommen die Abfahrten zusätzlich direkt vom Verkehrsverbund Berlin-Brandenburg über [v6.vbb.transport.rest](https://v6.vbb.transport.rest).

Beide Dienste sind kostenlos und brauchen keinen Zugangsschlüssel. Die App schickt nur den ungefähren Standort für die Haltestellensuche und das Suchziel dorthin – sonst nichts.

## Selbst bauen

Gebraucht wird ein Mac mit Xcode 26 und ein iPhone mit iOS 26 oder neuer.

1. `Gleich.xcodeproj` öffnen.
2. Für die Ziele „Gleich“ und „GleichWidgetExtension“ unter „Signing & Capabilities“ das eigene Team wählen.
   Wer eine andere Apple-ID hat, ändert die Kennung (`com.fmoniac.Gleich`) und die App Group (`group.com.fmoniac.Gleich`).
3. iPhone auswählen und auf ▶ klicken.

Das App-Symbol zeichnet `Tools/appsymbol.sh` aus derselben Lok, die in der App tuckert.

## Lizenz

MIT – siehe `LICENSE`.
