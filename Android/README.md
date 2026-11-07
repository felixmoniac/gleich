# Gleich für Android

Die Android-Fassung von Gleich – gleiche Bedienung wie auf dem iPhone, geschrieben in Kotlin mit Jetpack Compose.
Die iPhone-Fassung liegt unverändert eine Ebene höher.

## Aufs Telefon bringen

`Gleich.apk` (rund 2,4 MB) aufs Android-Gerät kopieren – per Kabel, Mail an sich selbst oder Cloud-Speicher – und dort
antippen. Android fragt einmal, ob Apps aus dieser Quelle installiert werden dürfen; das erlauben. Fertig.

## Was anders ist als auf dem iPhone

- **Fußweg:** öffnet Google Maps statt Apple Karten (ohne Google Maps im Browser).
- **Gehzeiten:** kommen vom freien Fußgänger-Router von OpenStreetMap (routing.openstreetmap.de) statt von Apple Karten.
- **Zurück:** Wisch nach rechts von überall auf der Seite – oder die normale Android-Zurück-Geste.
- **Zeitwahl:** Tag antippen, Uhrzeit auf dem Zifferblatt statt Drehrad.
- **Widget:** nur fürs Startbildschirm (Android hat keine Sperrbildschirm-Widgets). Es zeigt Uhrzeiten statt
  „in 4 Min“, weil Android-Widgets nicht jede Minute neu gezeichnet werden, und nimmt den Standort, den die App zuletzt
  kannte (ohne Sondererlaubnis darf Android im Hintergrund keinen neuen abfragen).

## Selbst bauen

```
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
./gradlew assembleRelease
```

Die fertige Datei liegt dann unter `app/build/outputs/apk/release/app-release.apk`.
