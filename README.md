# Gleich

Eine schlichte Fahrplan-App fürs iPhone. Beim Öffnen zeigt sie sofort, was an der nächsten Haltestelle abfährt – überall in Deutschland.

## Was die App kann

- **Abfahrten in der Nähe:** Oben steht der Name der Haltestelle, darunter Linie, Richtung und Minuten bis zur Abfahrt.
  Linien erscheinen in ihren gewohnten Farben (S-Bahn rund, U-Bahn eckig, Tram rot, Bus lila).
  Gezeigt werden höchstens 15 Abfahrten, je Linie höchstens vier und je Richtung zwei – so wiederholt sich an kleinen
  Haltestellen nicht ständig dieselbe Linie, und an großen Bahnhöfen bleibt es übersichtlich.
  Eine rote Zeit heißt: Der Zug ist verspätet, angezeigt wird die tatsächliche Abfahrt.
  Blasse Zeilen schafft man zu Fuß wahrscheinlich nicht mehr – mit etwas Glück aber doch.
- **Große Bahnhöfe** gelten als eine Haltestelle. Dann erscheinen oben kleine Symbole für die Verkehrsmittel (S, U, Tram, Bus, Zug); ein Tipp zeigt nur dieses Verkehrsmittel.
- **Wischen nach links** zeigt weitere Haltestellen – aber nur solche, an denen etwas fährt, das es an der nächsten nicht gibt:
  erst bis 6 Minuten zu Fuß, dann Bahnhöfe bis 30 Minuten (zum Beispiel der Regionalzug, der von der Bushaltestelle aus
  nicht fährt), dann andere Buslinien bis 15 Minuten. Höchstens vier Haltestellen; neben dem Namen steht die Gehzeit.
  Die Gehzeiten rechnet Apple Karten auf echten Wegen – ein See, über den keine Brücke führt, wird umlaufen.
  Fahren an zwei Bahnhöfen dieselben Linien, gewinnt der mit dem kürzeren Fußweg. Ohne Netz gilt die Luftlinie.
- **Wischen nach rechts** öffnet die Übersicht: der Verkehrsverbund, in dem man gerade ist, seine Netzpläne und eine kurze Anleitung.
  Die Netzpläne lädt die App von selbst herunter, sie sind danach auch ohne Netz da. Ein Tipp öffnet den Plan zum Zoomen.
  Netzpläne gibt es bisher für Berlin-Brandenburg (VBB), Hamburg (HVV), München (MVV), Rhein-Main (RMV), Rhein-Ruhr (VRR),
  Köln/Bonn (VRS), Stuttgart (VVS) und Dresden (VVO). Jeder Verbund stellt seine Pläne selbst ins Netz; die App liest dafür
  die Übersichtsseiten der Verbünde.
  Welcher Verbund gilt, erkennt die App am Standort (Ortspfeil vor dem Namen). Ein Tipp auf den Namen lässt einen
  anderen Verbund wählen (Stecknadel) oder zurück auf „Automatisch“ stellen. Das betrifft nur die Netzpläne –
  Abfahrten und Verbindungen kommen immer vom tatsächlichen Standort.
- Beim ersten Start erklärt ein kleiner Kasten, was geht.
- **Antippen einer Abfahrt** zeigt die weiteren Halte mit Uhrzeit. **Antippen des Haltestellennamens** öffnet den Fußweg in Apple Karten; langes Drücken bietet „Merken“ an.
- **Suche unten („Wohin?“):** die nächsten sechs Verbindungen von hier, ab jetzt. Gemerkte Orte („Zuhause“, „Arbeit“ …) stehen ganz oben. Ein Tipp auf eine Verbindung klappt die einzelnen Schritte auf.
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
