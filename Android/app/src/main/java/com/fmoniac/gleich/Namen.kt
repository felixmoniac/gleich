package com.fmoniac.gleich

/** Macht Haltestellennamen kurz und lesbar: „S+U Alexanderplatz Bhf (Berlin)“ → „Alexanderplatz“. */
object Namen {
    fun kurz(name: String, ort: String? = null): String {
        var s = name.trim()
        for (klammer in listOf(" (Berlin)", " (Bln)", " (Potsdam)")) s = s.replace(klammer, "")
        for (vorne in listOf("S+U ", "S+U-", "U+S ", "S ", "U ")) {
            if (s.startsWith(vorne)) {
                s = s.removePrefix(vorne)
                break
            }
        }
        for ((alt, neu) in listOf(", Hauptbahnhof" to " Hbf", ", Hbf" to " Hbf", ", Bahnhof" to "", ", Bhf" to "")) {
            if (s.endsWith(alt)) s = s.dropLast(alt.length) + neu
        }
        for (hinten in listOf(" Bhf", " Bahnhof")) {
            if (s.endsWith(hinten) && s.length > hinten.length + 3) s = s.dropLast(hinten.length)
        }
        if (!ort.isNullOrEmpty()) {
            for (trenner in listOf(", ", " ")) {
                val rest = s.drop(ort.length + trenner.length)
                if (s.startsWith(ort + trenner) && s.length > ort.length + 4 && rest !in listOf("Hbf", "Hauptbahnhof")) {
                    s = rest
                    break
                }
            }
        }
        return s
    }

    /** Ort aus „Potsdam, Lange Brücke“ → „Potsdam“. */
    fun ortAus(name: String): String? {
        val komma = name.indexOf(',')
        if (komma < 0) return null
        return name.substring(0, komma).trim().ifEmpty { null }
    }

    /** Häufigster Ort unter den Haltestellen in der Nähe. */
    fun ortUnter(namen: List<String>): String? =
        namen.mapNotNull(::ortAus).groupingBy { it }.eachCount().maxByOrNull { it.value }?.key

    /** Vergleichsform, um Teile desselben Bahnhofs zu erkennen. */
    fun kern(name: String): String =
        kurz(name).lowercase().replace("hauptbahnhof", "hbf").filter { it.isLetterOrDigit() }
}
