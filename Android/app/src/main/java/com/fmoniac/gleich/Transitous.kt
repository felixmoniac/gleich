package com.fmoniac.gleich

import kotlinx.serialization.json.JsonObject
import java.util.UUID

/** Freier Fahrplandienst für ganz Deutschland (und darüber hinaus): https://transitous.org */
object Transitous {
    private const val BASIS = "https://api.transitous.org/api"

    fun mittel(s: String?): Verkehrsmittel = when (s ?: "") {
        "HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL" -> Verkehrsmittel.fern
        "REGIONAL_FAST_RAIL", "REGIONAL_RAIL", "RAIL" -> Verkehrsmittel.regio
        "SUBURBAN" -> Verkehrsmittel.sbahn
        "SUBWAY", "METRO" -> Verkehrsmittel.ubahn
        "TRAM", "CABLE_CAR", "FUNICULAR" -> Verkehrsmittel.tram
        "BUS", "COACH" -> Verkehrsmittel.bus
        "FERRY" -> Verkehrsmittel.faehre
        else -> Verkehrsmittel.sonst
    }

    fun linie(d: JsonObject): Linie {
        val name = d.text("displayName") ?: d.text("routeShortName") ?: d.text("tripShortName") ?: "?"
        return Linie(name, mittel(d.text("mode")), d.text("routeColor"))
    }

    // Haltestellen in der Nähe

    suspend fun haltestellen(ort: Ort): List<Haltestelle> {
        val j = Netz.json(BASIS, "/v1/reverse-geocode", mapOf("place" to "${ort.breite},${ort.laenge}", "type" to "STOP"))
        val nah = j.arr().mapNotNull { haltestelle(it.obj() ?: return@mapNotNull null) }
        // Die Umkreissuche reicht nur etwa einen Kilometer weit. Für Bahnhöfe etwas weiter weg
        // und auf dem Land im Kartenausschnitt suchen, notfalls großzügig.
        for (spanne in listOf(0.018, 0.06, 0.3)) {
            val weit = try { imAusschnitt(ort, spanne) } catch (_: Exception) { emptyList() }
            if (weit.isNotEmpty() || nah.isNotEmpty()) return nah + weit
        }
        return nah
    }

    private fun haltestelle(d: JsonObject): Haltestelle? {
        val id = d.text("id") ?: d.text("stopId") ?: return null
        val name = d.text("name") ?: return null
        val b = d.zahl("lat") ?: return null
        val l = d.zahl("lon") ?: return null
        val modi = d["modes"].arr().mapNotNull { (it as? kotlinx.serialization.json.JsonPrimitive)?.content }.map(::mittel)
        return Haltestelle(d.text("parentId") ?: id, name, b, l, Quelle.transitous, modi.distinct())
    }

    private suspend fun imAusschnitt(o: Ort, spanne: Double): List<Haltestelle> {
        val breit = spanne * 1.6
        val j = Netz.json(BASIS, "/v1/map/stops", mapOf(
            "min" to "${o.breite - spanne},${o.laenge - breit}",
            "max" to "${o.breite + spanne},${o.laenge + breit}",
        ))
        val alle = j.arr().mapNotNull { it.obj()?.let(::haltestelle) }.sortedBy { it.ort.abstand(o) }
        // Teile desselben Halts zusammenführen, ihre Verkehrsmittel dabei sammeln.
        val nachName = LinkedHashMap<String, Haltestelle>()
        for (h in alle) {
            val k = Namen.kern(h.name)
            val da = nachName[k]
            nachName[k] = if (da != null) da.copy(mittel = (da.mittel + h.mittel).distinct()) else h
        }
        return nachName.values.take(40)
    }

    // Abfahrten

    data class Seite(val abfahrten: List<Abfahrt>, val weiter: String?)

    suspend fun abfahrten(halt: Haltestelle, weiter: String? = null): Seite {
        val j = Netz.json(BASIS, "/v5/stoptimes", mapOf(
            "stopId" to halt.id,
            "n" to "40",
            "pageCursor" to weiter,
            "withAlerts" to "false",
        )).obj() ?: JsonObject(emptyMap())
        val gesehen = HashSet<String>()
        val ergebnis = mutableListOf<Abfahrt>()
        for (d in j.liste("stopTimes")) {
            val platz = d.objekt("place") ?: continue
            val geplant = platz.datum("scheduledDeparture") ?: continue
            val linie = linie(d)
            val richtung = d.text("headsign") ?: d.objekt("tripTo")?.text("name") ?: ""
            // Dieselbe Fahrt steckt manchmal in zwei Datensätzen (bundesweit und VBB).
            if (!gesehen.add("${linie.name}|${Namen.kern(richtung)}|$geplant")) continue
            val echt = if (d.wahr("realTime")) platz.datum("departure") else null
            ergebnis += Abfahrt(
                id = (d.text("tripId") ?: UUID.randomUUID().toString()) + (platz.text("stopId") ?: ""),
                linie = linie,
                richtung = richtung,
                geplant = geplant,
                echt = echt,
                gleis = if (linie.mittel.istZug || linie.mittel == Verkehrsmittel.sbahn) platz.text("track") else null,
                faelltAus = d.wahr("cancelled") || d.wahr("tripCancelled") || platz.wahr("cancelled"),
                fahrtID = d.text("tripId") ?: "",
                quelle = Quelle.transitous,
                halt = platz.text("name") ?: halt.name,
            )
        }
        return Seite(ergebnis, j.text("nextPageCursor"))
    }

    // Fahrtverlauf

    suspend fun verlauf(fahrt: String, ab: String): List<Zwischenhalt> {
        val j = Netz.json(BASIS, "/v5/trip", mapOf("tripId" to fahrt)).obj() ?: return emptyList()
        val abschnitt = j.liste("legs").firstOrNull { it.text("mode") != "WALK" } ?: return emptyList()
        val halte = buildList {
            abschnitt.objekt("from")?.let(::add)
            addAll(abschnitt.liste("intermediateStops"))
            abschnitt.objekt("to")?.let(::add)
        }
        val alle = halte.mapIndexed { i, h ->
            Zwischenhalt(
                id = i,
                name = h.text("name") ?: "",
                geplant = h.datum("scheduledDeparture") ?: h.datum("scheduledArrival"),
                echt = h.datum("departure") ?: h.datum("arrival"),
                faelltAus = h.wahr("cancelled"),
            )
        }
        val kern = Namen.kern(ab)
        val start = alle.indexOfFirst { Namen.kern(it.name).startsWith(kern) || kern.startsWith(Namen.kern(it.name)) }
        return if (start >= 0) alle.drop(start) else alle
    }

    // Ziele suchen

    suspend fun suchen(text: String, nahe: Ort?): List<Ziel> {
        val j = Netz.json(BASIS, "/v1/geocode", mapOf(
            "text" to text,
            "place" to nahe?.let { "${it.breite},${it.laenge}" },
            "language" to "de",
        ))
        val gesehen = HashSet<String>()
        val ziele = j.arr().mapNotNull { e ->
            val d = e.obj() ?: return@mapNotNull null
            val roh = d.text("name") ?: return@mapNotNull null
            val b = d.zahl("lat") ?: return@mapNotNull null
            val l = d.zahl("lon") ?: return@mapNotNull null
            val typ = d.text("type")
            val gebiet = d.liste("areas").firstOrNull { it.wahr("default") }?.text("name")
            var name = if (typ == "STOP") Namen.kurz(roh, gebiet) else roh
            val strasse = d.text("street")
            if (typ == "ADDRESS" && strasse != null) {
                name = strasse + (d.text("houseNumber")?.let { " $it" } ?: "")
            }
            if (!gesehen.add(Namen.kern(name) + (gebiet ?: ""))) return@mapNotNull null
            val zusatz = gebiet?.takeIf { !name.contains(it) }
            val ziel = Ziel(d.text("id") ?: roh, name, zusatz, b, l, if (typ == "STOP") d.text("id") else null)
            val fern = nahe?.let { Ort(b, l).abstand(it) > 150_000 } ?: false
            ziel to fern
        }
        // Was in der Nähe liegt, zuerst; die Reihenfolge des Dienstes bleibt sonst erhalten.
        return ziele.filter { !it.second }.map { it.first } + ziele.filter { it.second }.map { it.first }
    }

    // Verbindungen

    suspend fun verbindungen(von: Ort, nach: Ziel, ab: Long? = null): List<Verbindung> {
        val j = Netz.json(BASIS, "/v5/plan", mapOf(
            "fromPlace" to "${von.breite},${von.laenge}",
            "toPlace" to nach.anfrage,
            "time" to ab?.let(Zeit::schreiben),
            "numItineraries" to "6",
            "withFares" to "false",
            "detailedTransfers" to "false",
        )).obj() ?: return emptyList()
        val liste = j.liste("itineraries").mapIndexed { nr, it ->
            Verbindung(
                id = it.text("id") ?: "$nr",
                abschnitte = it.liste("legs").mapIndexedNotNull { i, l -> abschnitt(l, i, nach) },
            )
        }
        return liste.filter { it.abschnitte.isNotEmpty() }.sortedWith(compareBy({ it.ab }, { it.an }))
    }

    private fun abschnitt(l: JsonObject, nr: Int, ziel: Ziel): Abschnitt? {
        val von = l.objekt("from") ?: return null
        val nach = l.objekt("to") ?: return null
        val ab = l.datum("scheduledStartTime") ?: l.datum("startTime") ?: return null
        val an = l.datum("scheduledEndTime") ?: l.datum("endTime") ?: return null
        val zuFuss = (l.text("mode") ?: "") in listOf("WALK", "BIKE", "CAR")
        val echt = l.wahr("realTime")
        fun name(p: JsonObject, standard: String): String {
            val n = p.text("name") ?: standard
            return when (n) {
                "START" -> "Hier"
                "END" -> ziel.name
                else -> n
            }
        }
        return Abschnitt(
            id = nr,
            linie = if (zuFuss) null else linie(l),
            richtung = l.text("headsign") ?: "",
            von = name(von, "Hier"),
            nach = name(nach, ziel.name),
            abGeplant = ab,
            abEcht = if (echt) l.datum("startTime") else null,
            anGeplant = an,
            anEcht = if (echt) l.datum("endTime") else null,
            gleis = if (zuFuss) null else von.text("track"),
            meter = l.zahl("distance"),
            fahrtID = l.text("tripId"),
            zwischenhalte = l.liste("intermediateStops").mapIndexed { i, h ->
                Zwischenhalt(
                    id = i,
                    name = h.text("name") ?: "",
                    geplant = h.datum("scheduledDeparture") ?: h.datum("scheduledArrival"),
                    echt = if (echt) h.datum("departure") ?: h.datum("arrival") else null,
                )
            },
        )
    }
}
