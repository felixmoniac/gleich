package com.fmoniac.gleich

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.util.Base64
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

@Serializable
data class Netzplan(val titel: String, val adresse: String) {
    val id: String get() = adresse

    /** Wo die heruntergeladene Datei liegt. */
    fun datei(ordner: File): File {
        val name = Base64.encodeToString(adresse.toByteArray(), Base64.NO_WRAP).filter { it.isLetterOrDigit() }.takeLast(60)
        return File(ordner, "$name.pdf")
    }
}

/**
 * Ein Verkehrsverbund und wo seine Netzpläne zu finden sind.
 * Es gibt keine gemeinsame Quelle für ganz Deutschland – jeder Verbund stellt seine Pläne selbst ins Netz.
 * Wo möglich, liest die App die Übersichtsseite des Verbunds, damit neue Ausgaben von selbst gefunden werden.
 */
data class Verbund(
    val name: String,
    val kuerzel: String,
    val breite: ClosedFloatingPointRange<Double>,
    val laenge: ClosedFloatingPointRange<Double>,
    /** Übersichtsseiten mit PDF-Links. */
    val seiten: List<String> = emptyList(),
    /** Wichtige Pläne: Titel und ein Stück der Dateiadresse, an dem sie zu erkennen sind. */
    val feste: List<Pair<String, String>> = emptyList(),
    /** Pläne mit fester Adresse. */
    val direkt: List<Pair<String, String>> = emptyList(),
) {
    fun enthaelt(o: Ort) = o.breite in breite && o.laenge in laenge

    companion object {
        /** Reihenfolge zählt: Die kleineren Gebiete zuerst, Berlin-Brandenburg zuletzt. */
        val alle = listOf(
            Verbund("Verkehrsverbund Oberelbe", "VVO", 50.75..51.45, 13.2..14.5,
                seiten = listOf("https://www.vvo-online.de/de/linien-plaene/liniennetz/index.cshtml",
                    "https://www.vvo-online.de/de/linien-plaene/stadtverkehr/index.cshtml"),
                feste = listOf("Liniennetz VVO" to "VVO-Liniennetzplan-topografisch",
                    "Dresden" to "Liniennetzplan-Stadt-Dresden.pdf")),
            Verbund("Hamburger Verkehrsverbund", "HVV", 53.2..54.0, 9.2..10.8,
                direkt = listOf("Schnellbahn und Regionalverkehr" to
                    "https://www.hvv.de/resource/blob/120104/3ff58f395fa6e8d4818231b0573b0bc6/hvv_usar-plan.pdf")),
            Verbund("Münchner Verkehrs- und Tarifverbund", "MVV", 47.6..48.7, 11.0..12.6,
                seiten = listOf("https://www.mvv-muenchen.de/netz-plaene-medien/plaene/netzplaene/download/gesamtnetz/"),
                feste = listOf("S-Bahn, U-Bahn, Regionalzug" to "SUR_M_12",
                    "Innenraum mit Tram" to "SURTX_M",
                    "Tram" to "Tramnetz",
                    "Nachtnetz" to "Nachtnetz",
                    "Regionalbusse" to "Regio_0GESAMT")),
            Verbund("Rhein-Main-Verkehrsverbund", "RMV", 49.6..50.9, 7.8..10.2,
                seiten = listOf("https://www.vgf-ffm.de/en/tickets-fares-plans/route-plans"),
                feste = listOf("Schnellbahnplan" to "Schnellbahnplan_Grossraum",
                    "Regionalzüge" to "RegionalerSchienennetzplan",
                    "Frankfurt" to "Liniennetzplan_Frankfurt_2",
                    "Frankfurt Nachtnetz" to "Nachtnetzplan_Frankfurt")),
            Verbund("Verkehrsverbund Rhein-Ruhr", "VRR", 51.05..51.75, 6.2..7.6,
                seiten = listOf("https://www.vrr.de/de/fahrplan-mobilitaet/stadt-linien-netzplaene/"),
                feste = listOf("Schnellverkehrsplan" to "Schienenschnellverkehrsplan")),
            Verbund("Verkehrsverbund Rhein-Sieg", "VRS", 50.55..51.05, 6.5..7.75,
                seiten = listOf("https://www.vrs.de/en/verbindungen/liniennetz/rail-and-bus-network-plans"),
                feste = listOf("S-Bahn" to "SBahnNetz",
                    "Regionalverkehr NRW" to "NRW_Regionalverkehrsplan")),
            Verbund("Verkehrs- und Tarifverbund Stuttgart", "VVS", 48.55..49.05, 8.8..9.75,
                direkt = listOf("S-Bahn und Stadtbahn" to
                    "https://www.vvs.de/fileadmin/2_Verbindungen_und_Mobilitaet/2.3_Liniennetz_und_Tarifzonenplan/S-Bahn_Stadtbahn/Verbund_Schienennetz.pdf")),
            Verbund("Verkehrsverbund Berlin-Brandenburg", "VBB", 51.35..53.56, 11.26..14.77,
                seiten = listOf("https://www.vbb.de/unterwegs-im-vbb/liniennetze/"),
                feste = listOf("S- und U-Bahn Berlin" to "berlin-s-u-schnellbahn",
                    "Regionalverkehr" to "bahn-regionalverkehr-brandenburg-und-berlin.pdf")),
        )

        fun an(o: Ort): Verbund? = alle.firstOrNull { it.enthaelt(o) }
    }
}

/** Lädt die Netzpläne des Verbunds, in dem man gerade ist, und hält sie ohne Netz bereit. */
class Planablage(context: Context) {
    val ordner = File(context.filesDir, "Netzplaene").apply { mkdirs() }

    /** Der Verbund, dessen Pläne gerade gezeigt werden. */
    var verbund by mutableStateOf<Verbund?>(null)
        private set
    /** Der Verbund am Standort – auch wenn von Hand ein anderer gewählt ist. */
    var automatisch by mutableStateOf<Verbund?>(null)
        private set
    /** Von Hand gewählter Verbund (Kürzel); null heißt: automatisch nach Standort. */
    var wahl by mutableStateOf(Ablage.prefs.getString("verbundWahl", null))
        private set
    var plaene by mutableStateOf(Ablage.lesen(ListSerializer(Netzplan.serializer()), "netzplaene") ?: emptyList())
        private set
    /** Zählt fertige Downloads hoch, damit die Ansicht neu nachsieht, welche Pläne da sind. */
    var geladen by mutableIntStateOf(0)
        private set
    /** Nur der neueste Ladevorgang darf Ergebnisse eintragen. */
    private var lauf = 0
    private var stand: Triple<String, List<String>, Long>? = null
    private var letzterOrt: Pair<Ort, List<String>>? = null

    fun datei(p: Netzplan) = p.datei(ordner)

    /** Liegt der Plan schon auf dem Gerät? */
    fun istBereit(p: Netzplan): Boolean {
        @Suppress("UNUSED_VARIABLE") val beobachten = geladen
        return datei(p).exists()
    }

    suspend fun aktualisieren(o: Ort?, orteRoh: List<String>) {
        if (o != null) {
            letzterOrt = o to orteRoh
            automatisch = Verbund.an(o)
        }
        val v = wahl?.let { k -> Verbund.alle.firstOrNull { it.kuerzel == k } } ?: automatisch
        // Ortspläne nur, wenn der Verbund zum Standort gehört.
        val orte = if (v?.kuerzel == automatisch?.kuerzel) orteRoh else emptyList()
        lauf += 1
        val meiner = lauf
        if (verbund != null && verbund?.kuerzel != v?.kuerzel) plaene = emptyList()
        verbund = v
        if (v == null) {
            plaene = emptyList()
            return
        }
        // Höchstens alle sechs Stunden neu nachsehen, außer Verbund oder Ort haben gewechselt.
        stand?.let { s ->
            if (s.first == v.kuerzel && s.second == orte && System.currentTimeMillis() - s.third < 6 * 3600_000L) return
        }
        val liste = suchen(v, orte)
        if (meiner != lauf || liste.isEmpty()) return
        stand = Triple(v.kuerzel, orte, System.currentTimeMillis())
        plaene = liste
        Ablage.schreiben(ListSerializer(Netzplan.serializer()), liste, "netzplaene")
        for (p in liste) {
            if (!istBereit(p) && herunterladen(p)) geladen += 1
        }
    }

    /** Anderen Verbund von Hand wählen – null schaltet zurück auf automatisch. */
    suspend fun waehlen(kuerzel: String?) {
        wahl = kuerzel
        Ablage.prefs.edit().putString("verbundWahl", kuerzel).apply()
        aktualisieren(letzterOrt?.first, letzterOrt?.second ?: emptyList())
    }

    private suspend fun herunterladen(p: Netzplan): Boolean = withContext(Dispatchers.IO) {
        try {
            val v = URL(p.adresse).openConnection() as HttpURLConnection
            v.connectTimeout = 15_000
            v.readTimeout = 60_000
            v.setRequestProperty("User-Agent", Netz.KENNUNG)
            if (v.responseCode != 200) return@withContext false
            val ziel = datei(p)
            val tmp = File(ziel.path + ".tmp")
            v.inputStream.use { ein -> tmp.outputStream().use { ein.copyTo(it) } }
            v.disconnect()
            tmp.renameTo(ziel)
        } catch (_: Exception) {
            false
        }
    }

    /** Liest die Übersichtsseiten und wählt die wichtigen Pläne und die des aktuellen Orts aus. */
    private suspend fun suchen(v: Verbund, orte: List<String>): List<Netzplan> = withContext(Dispatchers.IO) {
        val gefunden = mutableListOf<Pair<String, String>>()
        for (seite in v.seiten) {
            try {
                val html = Netz.text(seite, kennung = "Mozilla/5.0 (Android) " + Netz.KENNUNG)
                gefunden += links(html, seite)
            } catch (_: Exception) {
            }
        }
        val ergebnis = mutableListOf<Netzplan>()
        fun dazu(titel: String, url: String) {
            if (ergebnis.none { it.adresse == url }) ergebnis += Netzplan(titel, url)
        }
        for ((titel, adresse) in v.direkt) dazu(titel, adresse)
        for ((titel, muster) in v.feste) {
            gefunden.firstOrNull { it.second.contains(muster, ignoreCase = true) }?.let { dazu(titel, it.second) }
        }
        // Pläne für den Ort, an dem man gerade ist (z. B. „Potsdam, Tageslinien“).
        val gesucht = orte.map(::vergleich).filter { it.length >= 4 }
        for ((titel, url) in gefunden) {
            val text = vergleich(titel + " " + url.substringAfterLast('/'))
            if (gesucht.any { text.contains(it) }) dazu(titel, url)
        }
        ergebnis.take(8)
    }

    private fun links(html: String, basis: String): List<Pair<String, String>> {
        val muster = Regex("""<a[^>]+href="([^"]+\.pdf[^"]*)"[^>]*>(.*?)</a>""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
        val roh = muster.findAll(html).mapNotNull { m ->
            val href = m.groupValues[1].replace("&amp;", "&")
            val url = try { URI(basis).resolve(href.replace(" ", "%20")).toString() } catch (_: Exception) { return@mapNotNull null }
            var text = m.groupValues[2].replace(Regex("<[^>]+>"), " ").replace("&amp;", "&")
                .split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
            // „Potsdam, Tageslinien: gültig ab …“ → „Potsdam, Tageslinien“
            text.indexOf(": gültig").takeIf { it >= 0 }?.let { text = text.substring(0, it) }
            text to url
        }.toList()
        // Oft gibt es zu einem Plan zwei Links: ein Bild ohne Text und den Titel. Der Titel gewinnt.
        val titel = HashMap<String, String>()
        for ((t, u) in roh) if (t.isNotEmpty() && u !in titel) titel[u] = t
        val gesehen = HashSet<String>()
        return roh.mapNotNull { (_, u) ->
            if (!gesehen.add(u)) return@mapNotNull null
            val t = titel[u] ?: u.substringAfterLast('/').substringBeforeLast('.').replace('_', ' ').replace('-', ' ')
            t to u
        }
    }

    private fun vergleich(s: String) = s.lowercase()
        .replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
        .filter { it.isLetter() }
}

/** Erste Seite eines PDFs als Bild – für Vorschau und Vollbild. */
object PdfBild {
    private val vorschau = HashMap<String, Bitmap>()

    fun seite(datei: File, breite: Int, zwischenspeichern: Boolean = false): Bitmap? {
        val schluessel = datei.path + "@" + breite
        if (zwischenspeichern) vorschau[schluessel]?.let { return it }
        return try {
            ParcelFileDescriptor.open(datei, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { r ->
                    r.openPage(0).use { s ->
                        val faktor = breite.toFloat() / s.width
                        val hoehe = (s.height * faktor).toInt().coerceAtMost(breite * 3)
                        val bild = Bitmap.createBitmap(breite, hoehe, Bitmap.Config.ARGB_8888)
                        bild.eraseColor(Color.WHITE)
                        s.render(bild, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        bild
                    }
                }
            }.also { if (zwischenspeichern) vorschau[schluessel] = it }
        } catch (_: Exception) {
            null
        }
    }
}
