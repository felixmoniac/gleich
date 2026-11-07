package com.fmoniac.gleich

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.Json

/**
 * Die eine Stelle, an der entschieden wird, woher die Daten kommen.
 * In Berlin/Brandenburg zuerst der VBB (bessere Live-Daten), sonst und als Ersatz Transitous.
 */
object Fahrplan {
    const val JWD_METER = 5000.0

    /** Alle Haltestellen der Umgebung, Teile desselben Bahnhofs zusammengelegt, nach Luftlinie sortiert. */
    suspend fun kandidaten(bei: Ort): List<Haltestelle> {
        var roh: List<Haltestelle> = emptyList()
        if (VBB.zustaendig(bei)) roh = try { VBB.haltestellen(bei) } catch (_: Exception) { emptyList() }
        if (roh.isEmpty()) roh = Transitous.haltestellen(bei)
        val alle = mutableListOf<Haltestelle>()
        for (h in roh.sortedBy { it.ort.abstand(bei) }) {
            val kern = Namen.kern(h.name)
            val i = alle.indexOfFirst { e ->
                val k = Namen.kern(e.name)
                (k == kern || kern.startsWith(k) || k.startsWith(kern)) && e.ort.abstand(h.ort) < 500
            }
            if (i >= 0) {
                // Teil desselben Bahnhofs oder die Haltestelle der Gegenrichtung: Linien übernehmen.
                alle[i] = alle[i].copy(
                    mittel = (alle[i].mittel + h.mittel).distinct(),
                    linien = (alle[i].linien + h.linien).distinct(),
                )
            } else {
                alle += h
            }
        }
        return alle
    }

    /**
     * Welche Haltestellen zur Auswahl stehen, gemessen in Minuten Fußweg: immer die nächste.
     * Weitere nur, wenn dort etwas fährt, das es näher nicht gibt – erst bis 6 Minuten, dann Bahnen bis 30,
     * dann Busse bis 15 Minuten. Bei gleichem Angebot gewinnt der kürzere Weg. Höchstens vier Haltestellen.
     */
    fun auswaehlen(alle: List<Haltestelle>, gehzeit: (Haltestelle) -> Double): List<Haltestelle> {
        val sortiert = alle.sortedBy(gehzeit)
        val naechste = sortiert.firstOrNull() ?: return emptyList()

        // Zum Vergleich: Linien, sonst (bei Transitous) Verkehrsmittel.
        fun angebot(h: Haltestelle): Set<String> =
            if (h.linien.isEmpty()) h.mittel.map { "${it.name}:" }.toSet() else h.linien.toSet()
        fun istBus(e: String) = e.startsWith("bus:") || e.startsWith("sonst:")

        val auswahl = mutableListOf(naechste)
        val durchgaenge: List<Pair<Double, (Set<String>) -> Boolean>> = listOf(
            6 * 60.0 to { s -> s.isNotEmpty() },
            30 * 60.0 to { s -> s.any { !istBus(it) } },
            15 * 60.0 to { s -> s.isNotEmpty() },
        )
        for ((sekunden, lohntSich) in durchgaenge) {
            for (h in sortiert) {
                if (auswahl.size >= 4 || h in auswahl || gehzeit(h) > sekunden) continue
                val bekannt = auswahl.flatMap(::angebot).toSet()
                if (lohntSich(angebot(h) - bekannt)) auswahl += h
            }
        }
        return auswahl.sortedBy(gehzeit)
    }

    suspend fun abfahrten(halt: Haltestelle): List<Abfahrt> = when (halt.quelle) {
        Quelle.vbb -> VBB.abfahrten(halt).sortedBy { it.zeit }
        Quelle.transitous -> Transitous.abfahrten(halt).abfahrten
    }

    suspend fun verlauf(a: Abfahrt): List<Zwischenhalt> = when (a.quelle) {
        Quelle.vbb -> VBB.verlauf(a.fahrtID, a.halt)
        Quelle.transitous -> Transitous.verlauf(a.fahrtID, a.halt)
    }

    /** Gehzeit nach Luftlinie: mal 1,3 für Umwege, 4,5 km/h. Ersatz, wenn kein echter Fußweg bekannt ist. */
    fun gehzeit(von: Ort?, zu: Haltestelle): Double {
        if (von == null) return 0.0
        return von.abstand(zu.ort) * 1.3 / 1.25
    }
}

/**
 * Echte Fußwege über den freien Fußgänger-Router von OpenStreetMap (routing.openstreetmap.de).
 * Luftlinie kennt keine Seen und keine Brücken; der Router schon (so gut die Karte eben ist).
 * Eine einzige Anfrage liefert die Gehzeiten zu allen Haltestellen.
 */
object Gehwege {
    private val json = Json { ignoreUnknownKeys = true }

    /** Gehzeit in Sekunden je Haltestelle. Was nicht innerhalb der Frist beantwortet ist, fehlt – dann gilt die Luftlinie. */
    suspend fun zeiten(von: Ort, zu: List<Haltestelle>, fristMs: Long = 8000): Map<String, Double> {
        if (zu.isEmpty()) return emptyMap()
        return withTimeoutOrNull(fristMs) {
            withContext(Dispatchers.IO) {
                try {
                    val punkte = (listOf(von) + zu.map { it.ort }).joinToString(";") { "${it.laenge},${it.breite}" }
                    val text = Netz.text(
                        "https://routing.openstreetmap.de/routed-foot/table/v1/driving/$punkte?sources=0",
                        frist = fristMs.toInt(),
                    )
                    val zeile = (json.parseToJsonElement(text).obj()?.get("durations") as? JsonArray)
                        ?.firstOrNull() as? JsonArray ?: return@withContext emptyMap()
                    buildMap {
                        zu.forEachIndexed { i, h ->
                            (zeile.getOrNull(i + 1) as? JsonPrimitive)?.doubleOrNull?.let { put(h.id, it) }
                        }
                    }
                } catch (_: Exception) {
                    emptyMap()
                }
            }
        } ?: emptyMap()
    }

    /**
     * Für welche Haltestellen sich das Nachfragen lohnt: die nahen und die Bahnhöfe in der weiteren Umgebung.
     * Was keine 150 m entfernt ist, bleibt bei der Luftlinie: Da steht man praktisch schon – und große Bahnhöfe
     * liegen in den Daten mitten auf den Gleisen, ein Router führt dann womöglich zu einer Straße auf der anderen Seite.
     */
    fun auswahl(alle: List<Haltestelle>, um: Ort): List<Haltestelle> {
        val weiter = alle.filter { it.ort.abstand(um) > 150 }
        val nah = weiter.filter { it.ort.abstand(um) <= 700 }.take(8)
        val bahn = weiter.filter { h ->
            h.ort.abstand(um) <= 2500 && h.mittel.any { it != Verkehrsmittel.bus && it != Verkehrsmittel.sonst }
        }.take(8)
        return (nah + bahn).distinctBy { it.id }
    }
}
