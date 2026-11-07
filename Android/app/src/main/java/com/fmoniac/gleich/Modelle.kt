package com.fmoniac.gleich

import kotlinx.serialization.Serializable

/** Verkehrsmittel – so grob, wie man sie im Alltag unterscheidet. */
@Serializable
enum class Verkehrsmittel {
    fern, regio, sbahn, ubahn, tram, bus, faehre, sonst;

    val istZug: Boolean get() = this == fern || this == regio

    companion object {
        /** Reihenfolge der Filter-Symbole oben in der Haltestelle. */
        val reihenfolge = listOf(fern, regio, sbahn, ubahn, tram, bus, faehre, sonst)
    }
}

@Serializable
data class Linie(
    val name: String,
    val mittel: Verkehrsmittel,
    /** Linienfarbe aus den Fahrplandaten (z. B. „816da6“), nur für S- und U-Bahn genutzt. */
    val farbe: String? = null,
)

@Serializable
enum class Quelle { transitous, vbb }

@Serializable
data class Haltestelle(
    val id: String,
    val name: String,
    val breite: Double,
    val laenge: Double,
    val quelle: Quelle,
    /** Was hier fährt – soweit die Datenquelle es verrät. */
    val mittel: List<Verkehrsmittel> = emptyList(),
    /** Linien, die hier halten (nur beim VBB bekannt), etwa „bus:607“. */
    val linien: List<String> = emptyList(),
) {
    val ort: Ort get() = Ort(breite, laenge)
}

/** Ein Punkt auf der Erde. */
@Serializable
data class Ort(val breite: Double, val laenge: Double) {
    /** Luftlinie in Metern. */
    fun abstand(zu: Ort): Double {
        val r = 6_371_000.0
        val b1 = Math.toRadians(breite)
        val b2 = Math.toRadians(zu.breite)
        val db = b2 - b1
        val dl = Math.toRadians(zu.laenge - laenge)
        val a = Math.sin(db / 2).let { it * it } + Math.cos(b1) * Math.cos(b2) * Math.sin(dl / 2).let { it * it }
        return 2 * r * Math.asin(Math.min(1.0, Math.sqrt(a)))
    }
}

/** Zeiten sind Millisekunden seit 1970. */
@Serializable
data class Abfahrt(
    val id: String,
    val linie: Linie,
    val richtung: String,
    val geplant: Long,
    val echt: Long? = null,
    val gleis: String? = null,
    val faelltAus: Boolean = false,
    val fahrtID: String,
    val quelle: Quelle,
    /** Name der Teil-Haltestelle, an der die Abfahrt stattfindet (für die Fahrtansicht). */
    val halt: String,
) {
    val zeit: Long get() = echt ?: geplant
    val verspaetet: Boolean get() = (echt ?: geplant) - geplant >= 60_000
}

data class Zwischenhalt(
    val id: Int,
    val name: String,
    val geplant: Long?,
    val echt: Long?,
    val faelltAus: Boolean = false,
) {
    val zeit: Long? get() = echt ?: geplant
    val verspaetet: Boolean
        get() = geplant != null && echt != null && echt - geplant >= 60_000
}

data class Abschnitt(
    val id: Int,
    /** null = Fußweg */
    val linie: Linie?,
    val richtung: String,
    val von: String,
    val nach: String,
    val abGeplant: Long,
    val abEcht: Long?,
    val anGeplant: Long,
    val anEcht: Long?,
    val gleis: String?,
    val meter: Double?,
    val fahrtID: String?,
    val zwischenhalte: List<Zwischenhalt>,
) {
    val ab: Long get() = abEcht ?: abGeplant
    val an: Long get() = anEcht ?: anGeplant
    val abVerspaetet: Boolean get() = ab - abGeplant >= 60_000
    val anVerspaetet: Boolean get() = an - anGeplant >= 60_000
    val istFussweg: Boolean get() = linie == null
}

data class Verbindung(val id: String, val abschnitte: List<Abschnitt>) {
    val fahrten: List<Abschnitt> get() = abschnitte.filter { !it.istFussweg }
    val ab: Long get() = abschnitte.firstOrNull()?.ab ?: System.currentTimeMillis()
    val an: Long get() = abschnitte.lastOrNull()?.an ?: System.currentTimeMillis()
    val abGeplant: Long get() = abschnitte.firstOrNull()?.abGeplant ?: System.currentTimeMillis()
    val anGeplant: Long get() = abschnitte.lastOrNull()?.anGeplant ?: System.currentTimeMillis()
}

/** Ein Ziel für die Suche: Haltestelle, Adresse oder Ort. */
@Serializable
data class Ziel(
    val id: String,
    val name: String,
    val zusatz: String? = null,
    val breite: Double,
    val laenge: Double,
    /** Haltestellen-Kennung bei Transitous, falls es eine Haltestelle ist. */
    val haltID: String? = null,
) {
    /** So versteht Transitous das Ziel. */
    val anfrage: String get() = haltID ?: "$breite,$laenge"
}

/** Was gesucht wird: wohin, und ab wann (null = jetzt). */
data class Fahrtwunsch(val ziel: Ziel, val ab: Long?)
