package com.fmoniac.gleich

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import java.net.URLEncoder
import java.util.UUID

/** Freie Schnittstelle des Verkehrsverbunds Berlin-Brandenburg: https://v6.vbb.transport.rest */
object VBB {
    private const val BASIS = "https://v6.vbb.transport.rest"

    /** Grob das Verbundgebiet. Liefert der VBB dort nichts, springt Transitous ein. */
    fun zustaendig(o: Ort): Boolean = o.breite in 51.35..53.56 && o.laenge in 11.26..14.77

    fun mittel(produkt: String?): Verkehrsmittel = when (produkt ?: "") {
        "express" -> Verkehrsmittel.fern
        "regional" -> Verkehrsmittel.regio
        "suburban" -> Verkehrsmittel.sbahn
        "subway" -> Verkehrsmittel.ubahn
        "tram" -> Verkehrsmittel.tram
        "bus" -> Verkehrsmittel.bus
        "ferry" -> Verkehrsmittel.faehre
        else -> Verkehrsmittel.sonst
    }

    private fun linie(l: JsonObject?): Linie {
        val farbe = l?.objekt("color")?.text("bg")?.replace("#", "")
        return Linie(l?.text("name") ?: "?", mittel(l?.text("product")), farbe)
    }

    suspend fun haltestellen(bei: Ort): List<Haltestelle> {
        val nah = haltestellen(bei, 2000, 30)
        if (nah.isNotEmpty()) return nah
        // Nichts in der Nähe: nur noch die nächste suchen, damit „JWD“ erkannt wird.
        return haltestellen(bei, 8000, 3)
    }

    private suspend fun haltestellen(o: Ort, meter: Int, anzahl: Int): List<Haltestelle> {
        val j = Netz.json(BASIS, "/locations/nearby", mapOf(
            "latitude" to "${o.breite}",
            "longitude" to "${o.laenge}",
            "results" to "$anzahl",
            "distance" to "$meter",
            "linesOfStops" to "true",
        ))
        return j.arr().mapNotNull { e ->
            val d = e.obj() ?: return@mapNotNull null
            val id = d.text("id") ?: return@mapNotNull null
            val name = d.text("name") ?: return@mapNotNull null
            val ort = d.objekt("location") ?: return@mapNotNull null
            val b = ort.zahl("latitude") ?: return@mapNotNull null
            val l = ort.zahl("longitude") ?: return@mapNotNull null
            val produkte = (d.objekt("products") ?: JsonObject(emptyMap()))
                .filter { (it.value as? JsonPrimitive)?.booleanOrNull == true }.keys
            // „tram:96“ – mit Verkehrsmittel, damit Bahnlinien Vorrang bekommen können.
            val linien = d.liste("lines").mapNotNull { l -> l.text("name")?.let { "${mittel(l.text("product")).name}:$it" } }
            Haltestelle(id, name, b, l, Quelle.vbb, produkte.map(::mittel).distinct(), linien.distinct())
        }
    }

    suspend fun abfahrten(halt: Haltestelle): List<Abfahrt> {
        val erste = abfahrten(halt, 60)
        // Auf dem Land fährt oft stundenlang nichts – dann weiter vorausschauen.
        return if (erste.isEmpty()) abfahrten(halt, 720) else erste
    }

    private suspend fun abfahrten(halt: Haltestelle, minuten: Int): List<Abfahrt> {
        val j = Netz.json(BASIS, "/stops/${halt.id}/departures", mapOf(
            "duration" to "$minuten",
            "results" to "60",
            "remarks" to "false",
        )).obj() ?: return emptyList()
        val kern = Namen.kern(halt.name)
        return j.liste("departures").mapNotNull { d ->
            val geplant = d.datum("plannedWhen") ?: return@mapNotNull null
            val teil = d.objekt("stop")?.text("name") ?: halt.name
            // Nur Teile desselben Bahnhofs, nicht die Nachbarhaltestelle um die Ecke.
            val k = Namen.kern(teil)
            if (!(k.startsWith(kern) || kern.startsWith(k))) return@mapNotNull null
            val linie = linie(d.objekt("line"))
            Abfahrt(
                id = (d.text("tripId") ?: UUID.randomUUID().toString()) + teil,
                linie = linie,
                richtung = d.text("direction") ?: d.objekt("destination")?.text("name") ?: "",
                geplant = geplant,
                echt = d.datum("when"),
                gleis = if (linie.mittel.istZug || linie.mittel == Verkehrsmittel.sbahn)
                    d.text("platform") ?: d.text("plannedPlatform") else null,
                faelltAus = d.wahr("cancelled"),
                fahrtID = d.text("tripId") ?: "",
                quelle = Quelle.vbb,
                halt = teil,
            )
        }
    }

    suspend fun verlauf(fahrt: String, ab: String): List<Zwischenhalt> {
        val id = URLEncoder.encode(fahrt, "UTF-8").replace("+", "%20")
        val j = Netz.json(BASIS, "/trips/$id", mapOf(
            "stopovers" to "true",
            "polyline" to "false",
            "remarks" to "false",
        )).obj() ?: return emptyList()
        val alle = (j.objekt("trip")?.liste("stopovers") ?: emptyList()).mapIndexed { i, s ->
            Zwischenhalt(
                id = i,
                name = s.objekt("stop")?.text("name") ?: "",
                geplant = s.datum("plannedDeparture") ?: s.datum("plannedArrival"),
                echt = s.datum("departure") ?: s.datum("arrival"),
                faelltAus = s.wahr("cancelled"),
            )
        }
        val kern = Namen.kern(ab)
        val start = alle.indexOfFirst { Namen.kern(it.name) == kern }
        return if (start >= 0) alle.drop(start) else alle
    }
}
