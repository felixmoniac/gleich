package com.fmoniac.gleich

import android.content.Context
import android.location.Geocoder
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import java.util.Locale

/** Zustand einer Haltestellen-Seite. */
class HaltModell(val halt: Haltestelle) {
    var abfahrten by mutableStateOf(Ablage.lesen(ListSerializer(Abfahrt.serializer()), "ab." + halt.id) ?: emptyList())
        private set
    var laedt by mutableStateOf(false)
        private set
    var ohneNetz by mutableStateOf(false)
        private set
    var filter by mutableStateOf<Verkehrsmittel?>(null)

    val id: String get() = halt.id

    /** Welche Verkehrsmittel hier fahren – für die Symbolreihe. */
    val mittel: List<Verkehrsmittel>
        get() {
            val da = abfahrten.map { it.linie.mittel }.toSet()
            return Verkehrsmittel.reihenfolge.filter { it in da }
        }

    /**
     * Nur die nächsten Abfahrten: insgesamt höchstens 15, je Linie höchstens vier, je Richtung höchstens zwei.
     * Von den blassen (zu Fuß wohl nicht mehr zu schaffen) zählt je Richtung nur eine mit –
     * sonst stünde dort womöglich nichts, was man noch erreicht.
     */
    fun sichtbar(jetzt: Long, erreichbar: (Abfahrt) -> Boolean): List<Abfahrt> {
        val jeLinie = HashMap<String, Int>()
        val jeRichtung = HashMap<String, IntArray>()
        val auswahl = abfahrten.filter { a ->
            if (a.zeit - jetzt <= -30_000 || (filter != null && a.linie.mittel != filter)) return@filter false
            val linie = a.linie.mittel.name + a.linie.name
            val richtung = linie + "|" + Namen.kern(a.richtung)
            val z = jeRichtung.getOrPut(richtung) { IntArray(2) }
            val blass = !erreichbar(a)
            if ((jeLinie[linie] ?: 0) >= 4 || z[0] >= 2 || (blass && z[1] >= 1)) return@filter false
            z[0] += 1
            if (blass) z[1] += 1
            jeLinie[linie] = (jeLinie[linie] ?: 0) + 1
            true
        }
        return auswahl.take(HOECHSTENS)
    }

    suspend fun laden() {
        laedt = true
        try {
            abfahrten = Fahrplan.abfahrten(halt)
            ohneNetz = false
            if (filter != null && filter !in mittel) filter = null
            Ablage.schreiben(ListSerializer(Abfahrt.serializer()), abfahrten, "ab." + halt.id)
        } catch (_: Exception) {
            ohneNetz = true
        } finally {
            laedt = false
        }
    }

    companion object {
        const val HOECHSTENS = 15
    }
}

/** Alles rund um „Wo bin ich, was fährt hier?“. */
class Umgebung(context: Context, private val bereich: CoroutineScope) {
    private val app = context.applicationContext
    val standort = Standort(app)
    val plaene = Planablage(app)

    var seiten by mutableStateOf<List<HaltModell>>(emptyList())
        private set
    var laedt by mutableStateOf(false)
        private set
    var ohneNetz by mutableStateOf(false)
        private set
    /**
     * Die App war zu: Die Haltestellen bleiben verborgen, bis der neue Standort sagt,
     * ob sie noch stimmen – sonst stünde in Bochum noch „Feldstraße“.
     */
    var veraltet by mutableStateOf(false)
        private set
    /** Nächste Haltestelle weiter als 5 km weg. */
    var jwd by mutableStateOf(false)
        private set
    /** Echte Gehzeiten (Sekunden je Haltestelle), vom Ort der letzten Haltestellensuche aus. */
    private var gehzeiten by mutableStateOf<Map<String, Double>>(emptyMap())
    private var ortDerHaltestellen: Ort? = null
    /** Kam während des Ladens ein neuer Auftrag (App kurz zu und wieder auf), wird danach noch einmal geladen. */
    private var nochmal = false

    /** Ortsname, der in allen Haltestellennamen steckt („Potsdam, …“) – wird beim Anzeigen weggelassen. */
    val ort: String? get() = Namen.ortUnter(seiten.map { it.halt.name })

    /** Die Haltestellen, die man sehen darf. */
    val sichtbar: List<HaltModell> get() = if (veraltet) emptyList() else seiten

    fun modell(id: String): HaltModell? = seiten.firstOrNull { it.id == id }

    /** Beim Schließen der App: alte Haltestellen nicht mehr zeigen. */
    fun zurueckgelassen() {
        veraltet = true
    }

    /** Standort holen, bei Bedarf Haltestellen neu suchen, dann die Abfahrten aller Haltestellen laden. */
    suspend fun allesNeu() {
        if (laedt) {
            nochmal = true
            return
        }
        laedt = true
        try {
            val hier = standort.frisch() ?: return
            val weit = ortDerHaltestellen?.let { it.abstand(hier) > 120 } ?: true
            if (weit && veraltet) {
                // Woanders aufgemacht: Die alten Haltestellen verschwinden sofort.
                seiten = emptyList()
                jwd = false
            }
            veraltet = false
            if (weit || seiten.isEmpty()) {
                try {
                    val alle = Fahrplan.kandidaten(hier)
                    gehzeiten = Gehwege.zeiten(hier, Gehwege.auswahl(alle, hier))
                    val liste = Fahrplan.auswaehlen(alle) { gehzeit(it, hier) }
                    ortDerHaltestellen = hier
                    ohneNetz = false
                    jwd = (liste.firstOrNull()?.ort?.abstand(hier) ?: Double.MAX_VALUE) > Fahrplan.JWD_METER
                    if (liste.map { it.id } != seiten.map { it.id }) {
                        val alt = seiten.associateBy { it.id }
                        seiten = liste.map { alt[it.id] ?: HaltModell(it) }
                    }
                } catch (e: Exception) {
                    android.util.Log.w("Gleich", "Haltestellen nicht geladen", e)
                    ohneNetz = true
                }
            }
            // Abfahrten aller Haltestellen im Hintergrund – beim Antippen sind sie schon da.
            coroutineScope { seiten.map { m -> async { m.laden() } }.awaitAll() }
            seiten.firstOrNull()?.let { ohneNetz = it.ohneNetz }
            GleichWidget.auffrischen(app)
            bereich.launch { netzplaene(hier) }
        } catch (e: Exception) {
            android.util.Log.w("Gleich", "Laden fehlgeschlagen", e)
        } finally {
            laedt = false
            if (nochmal) {
                nochmal = false
                bereich.launch { allesNeu() }
            }
        }
    }

    /** Netzpläne für den Verbund und den Ort, an dem man gerade ist. */
    private suspend fun netzplaene(hier: Ort) {
        val orte = mutableListOf<String>()
        withContext(Dispatchers.IO) {
            try {
                @Suppress("DEPRECATION")
                Geocoder(app, Locale.GERMANY).getFromLocation(hier.breite, hier.laenge, 1)
                    ?.firstOrNull()?.locality?.let(orte::add)
            } catch (_: Exception) {
            }
        }
        Namen.ortUnter(seiten.map { it.halt.name })?.let(orte::add)
        plaene.aktualisieren(hier, orte.distinct().sorted())
    }

    /** Fußweg zur Haltestelle: echt, wenn der Router ihn kennt, sonst nach Luftlinie. */
    fun gehzeit(halt: Haltestelle, von: Ort? = null): Double =
        gehzeiten[halt.id] ?: Fahrplan.gehzeit(von ?: standort.ort, halt)

    fun erreichbar(a: Abfahrt, halt: Haltestelle, jetzt: Long): Boolean =
        (a.zeit - jetzt) / 1000.0 >= gehzeit(halt)
}
