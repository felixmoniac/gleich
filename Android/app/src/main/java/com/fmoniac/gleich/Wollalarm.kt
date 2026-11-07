package com.fmoniac.gleich

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowLeft
import androidx.compose.material.icons.automirrored.filled.ArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.random.Random

/**
 * „Wollalarm“ – das versteckte Spiel: Die kleine Lok fährt unten hin und her und pustet Dampfwolken nach oben.
 * Von oben rückt eine Formation struppiger Katzen an, wirft Wollknäuel und wird schneller, je weniger übrig sind.
 * Prellböcke geben Deckung, ab und zu saust ein Kontrolleur vorbei. Alle Maße in dp.
 */
class Wollalarm(private val ruckeln: (Int) -> Unit) {
    enum class Phase { start, laeuft, ende }

    class Katze(val spalte: Int, val reihe: Int) { var lebt = true }
    class Prellbock(val x: Float, val y: Float) {
        /** 9 Reihen × 14 Steinchen: Balken oben, zwei Stützen darunter. */
        val zellen = Array(9) { reihe ->
            BooleanArray(14) { spalte ->
                when {
                    reihe == 0 -> spalte in 1..12
                    reihe <= 2 -> true
                    else -> spalte in 1..4 || spalte in 9..12
                }
            }
        }
    }
    class Blitz(val ort: Offset, val zeit: Double, val gross: Boolean)
    class Bonus(val text: String, val ort: Offset, val zeit: Double)

    companion object {
        const val SPALTEN = 9
        const val REIHEN = 5
        const val ZELLE = 3f
        /** Abstand zwischen zwei Wolken beim Dauerfeuer. */
        const val SCHUSS_TAKT = 0.2
        fun wert(reihe: Int) = if (reihe == 0) 30 else if (reihe < 3) 20 else 10
    }

    var phase = Phase.start
    var breite = 390f
    var hoehe = 700f
    var zeit = 0.0; private set
    var punkte = 0; private set
    var rekord = Ablage.prefs.getInt("wollalarm.rekord", 0); private set
    var leben = 3; private set
    private var welle = 0
    var lokX = 195f; private set
    /** Stellung der Wippe: −1 ganz links, 0 steht, +1 ganz rechts – dazwischen stufenlos. */
    var steuer = 0f
    var lokWeg = 0.0; private set
    var unverwundbarBis = 0.0; private set
    /** Dampfwolken unterwegs nach oben. */
    val schuesse = mutableListOf<Offset>()
    /** Wird die Dampftaste gehalten, pustet die Lok fortlaufend. */
    var dampfGehalten = false
    private var naechsterSchuss = 0.0
    val katzen = mutableListOf<Katze>()
    var versatz = Offset.Zero; private set
    private var richtung = 1f
    private var takt = 0.0
    var bild = false; private set
    val knaeuel = mutableListOf<Offset>()
    private var naechsterWurf = 1.2
    val prellboecke = mutableListOf<Prellbock>()
    var kontrolleur: Offset? = null; private set
    private var kontrolleurRichtung = 1f
    private var naechsterKontrolleur = 18.0
    val blitze = mutableListOf<Blitz>()
    var bonus: Bonus? = null; private set

    private val abstandX get() = min(40f, breite * 0.09f)
    private val abstandY = 30f
    /** Unten bleibt Platz für die Tasten. */
    val lokY get() = hoehe - 150f
    private val schornsteinX get() = lokX + (58 - 37) * 0.7f

    fun ort(k: Katze): Offset {
        val b = (SPALTEN - 1) * abstandX
        return Offset((breite - b) / 2 + versatz.x + k.spalte * abstandX, 110 + versatz.y + k.reihe * abstandY)
    }

    /** Dampftaste gedrückt: schießt sofort (oder startet ein neues Spiel), danach Dauerfeuer bis zum Loslassen. */
    fun dampf(gedrueckt: Boolean) {
        dampfGehalten = gedrueckt
        if (!gedrueckt) return
        if (phase == Phase.laeuft) feuern() else neuesSpiel()
    }

    /** Tipp aufs Spielfeld startet nur, schießt aber nicht. */
    fun starten() {
        if (phase != Phase.laeuft) neuesSpiel()
    }

    private fun neuesSpiel() {
        punkte = 0
        leben = 3
        welle = 0
        lokX = breite / 2
        unverwundbarBis = 0.0
        bonus = null
        blitze.clear()
        kontrolleur = null
        naechsterKontrolleur = Random.nextDouble(15.0, 25.0)
        prellboecke.clear()
        val b = 14 * ZELLE
        for (i in 0 until 4) prellboecke += Prellbock(breite * (i + 0.5f) / 4 - b / 2, lokY - 78)
        neueWelle()
        phase = Phase.laeuft
    }

    private fun neueWelle() {
        katzen.clear()
        for (r in 0 until REIHEN) for (s in 0 until SPALTEN) katzen += Katze(s, r)
        // Jede Welle startet ein Stück tiefer
        versatz = Offset(0f, min(welle, 5) * 14f)
        richtung = 1f
        takt = 0.0
        knaeuel.clear()
        schuesse.clear()
        naechsterWurf = 1.5
    }

    private fun feuern() {
        if (zeit < naechsterSchuss || zeit <= unverwundbarBis) return
        schuesse += Offset(schornsteinX, lokY - 30)
        naechsterSchuss = zeit + SCHUSS_TAKT
    }

    /** Ein Zeitschritt. */
    fun schritt(dt: Double) {
        zeit += dt
        blitze.removeAll { zeit - it.zeit > 0.35 }
        bonus?.let { if (zeit - it.zeit > 1.2) bonus = null }
        if (phase != Phase.laeuft) return

        // Lok fährt, solange die Wippe gedrückt ist
        if (zeit > unverwundbarBis - 0.6) {
            val neu = (lokX + steuer * (360 * dt).toFloat()).coerceIn(30f, breite - 30f)
            lokWeg += (neu - lokX) / 6.0
            lokX = neu
        }

        if (dampfGehalten) feuern()
        bewegeSchuesse(dt)

        // Formation: je weniger Katzen, desto schneller
        val lebend = katzen.count { it.lebt }
        val intervall = max(0.03, 0.04 + 0.55 * lebend / katzen.size - min(welle, 5) * 0.03)
        takt += dt
        while (takt >= intervall) {
            takt -= intervall
            formationsSchritt()
        }

        naechsterWurf -= dt
        if (naechsterWurf <= 0) {
            werfen()
            naechsterWurf = Random.nextDouble(0.5, 1.3) * max(0.45, 1 - welle * 0.1)
        }
        bewegeKnaeuel(dt)
        bewegeKontrolleur(dt)

        // Katzen unten angekommen: verloren
        if (katzen.any { it.lebt && ort(it).y > lokY - 34 }) {
            beenden()
            return
        }
        if (lebend == 0) {
            welle += 1
            neueWelle()
        }
    }

    private fun formationsSchritt() {
        val lebende = katzen.filter { it.lebt }.map(::ort)
        val links = lebende.minOfOrNull { it.x } ?: return
        val rechts = lebende.maxOf { it.x }
        val rand = 18f
        versatz = if ((richtung > 0 && rechts + 6 > breite - rand) || (richtung < 0 && links - 6 < rand)) {
            richtung *= -1
            versatz + Offset(0f, 14f)
        } else {
            versatz + Offset(6 * richtung, 0f)
        }
        bild = !bild
    }

    private fun bewegeSchuesse(dt: Double) {
        val bleiben = mutableListOf<Offset>()
        for (s0 in schuesse) {
            val s = s0 - Offset(0f, (560 * dt).toFloat())
            if (s.y < 40) continue
            if (treffer(s)) continue
            bleiben += s
        }
        schuesse.clear(); schuesse += bleiben
    }

    /** Trifft eine Wolke etwas? Katze, Kontrolleur oder Prellbock. */
    private fun treffer(s: Offset): Boolean {
        for (k in katzen) {
            if (!k.lebt) continue
            val o = ort(k)
            if (abs(s.x - o.x) < 13 && abs(s.y - o.y) < 12) {
                k.lebt = false
                gewinnen(wert(k.reihe))
                blitze += Blitz(o, zeit, false)
                ruckeln(0)
                return true
            }
        }
        kontrolleur?.let { k ->
            if (abs(s.x - k.x) < 18 && abs(s.y - k.y) < 14) {
                val extra = listOf(50, 100, 150, 300).random()
                gewinnen(extra)
                bonus = Bonus("+$extra", k, zeit)
                blitze += Blitz(k, zeit, true)
                kontrolleur = null
                ruckeln(1)
                return true
            }
        }
        return trifftPrellbock(s)
    }

    private fun werfen() {
        val spalte = katzen.filter { it.lebt }.map { it.spalte }.distinct().randomOrNull() ?: return
        val unterste = katzen.filter { it.lebt && it.spalte == spalte }.maxByOrNull { it.reihe } ?: return
        val o = ort(unterste)
        knaeuel += Offset(o.x, o.y + 12)
    }

    private fun bewegeKnaeuel(dt: Double) {
        val bleiben = mutableListOf<Offset>()
        for (k0 in knaeuel) {
            val k = k0 + Offset(0f, ((190 + min(welle, 5) * 15.0) * dt).toFloat())
            if (k.y > hoehe) continue
            if (trifftPrellbock(k)) continue
            if (zeit > unverwundbarBis && abs(k.x - lokX) < 24 && k.y > lokY - 28 && k.y < lokY + 6) {
                getroffen()
                return
            }
            bleiben += k
        }
        knaeuel.clear(); knaeuel += bleiben
    }

    private fun getroffen() {
        leben -= 1
        blitze += Blitz(Offset(lokX, lokY - 14), zeit, true)
        ruckeln(2)
        unverwundbarBis = zeit + 1.6
        knaeuel.clear()
        if (leben <= 0) beenden()
    }

    private fun bewegeKontrolleur(dt: Double) {
        kontrolleur?.let { k ->
            val n = k + Offset(kontrolleurRichtung * (85 * dt).toFloat(), 0f)
            kontrolleur = if (n.x < -30 || n.x > breite + 30) null else n
            return
        }
        naechsterKontrolleur -= dt
        if (naechsterKontrolleur <= 0) {
            kontrolleurRichtung = if (Random.nextBoolean()) 1f else -1f
            kontrolleur = Offset(if (kontrolleurRichtung > 0) -25f else breite + 25, 70f)
            naechsterKontrolleur = Random.nextDouble(18.0, 30.0)
        }
    }

    /** Trifft der Punkt ein Steinchen? Dann bröckeln es und ein, zwei Nachbarn weg. */
    private fun trifftPrellbock(p: Offset): Boolean {
        for (b in prellboecke) {
            if (p.x < b.x || p.y < b.y) continue
            val spalte = ((p.x - b.x) / ZELLE).toInt()
            val reihe = ((p.y - b.y) / ZELLE).toInt()
            if (reihe >= 9 || spalte >= 14 || !b.zellen[reihe][spalte]) continue
            b.zellen[reihe][spalte] = false
            repeat(3) {
                val r = reihe + Random.nextInt(-1, 2)
                val s = spalte + Random.nextInt(-1, 2)
                if (r in 0 until 9 && s in 0 until 14) b.zellen[r][s] = false
            }
            return true
        }
        return false
    }

    private fun gewinnen(n: Int) {
        punkte += n
        if (punkte > rekord) {
            rekord = punkte
            Ablage.prefs.edit().putInt("wollalarm.rekord", rekord).apply()
        }
    }

    private fun beenden() {
        phase = Phase.ende
        knaeuel.clear()
        schuesse.clear()
        dampfGehalten = false
        ruckeln(2)
    }
}

@Composable
fun WollalarmSpiel(schliessen: () -> Unit) {
    val haptik = LocalHapticFeedback.current
    val spiel = remember {
        Wollalarm { staerke ->
            haptik.performHapticFeedback(if (staerke == 0) HapticFeedbackType.TextHandleMove else HapticFeedbackType.LongPress)
        }
    }
    var bildNr by remember { mutableLongStateOf(0L) }
    LaunchedEffect(Unit) {
        var vorher = withFrameNanos { it }
        while (true) {
            withFrameNanos { jetzt ->
                spiel.schritt(min(0.05, (jetzt - vorher) / 1e9))
                vorher = jetzt
                bildNr++
            }
        }
    }
    // Punkte und Spielstand werden bei jedem Bild nachgesehen, die Anzeige baut sich aber nur neu auf, wenn sie sich ändern.
    val punkte by remember { derivedStateOf { bildNr; spiel.punkte } }
    val phase by remember { derivedStateOf { bildNr; spiel.phase } }
    val farbe = MaterialTheme.colorScheme.onBackground
    val messer = rememberTextMeasurer()

    androidx.activity.compose.BackHandler(onBack = schliessen)
    Box(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            // Berührungen landen beim Spiel, nicht bei der Startseite darunter.
            .pointerInput(Unit) { awaitEachGesture { awaitFirstDown(requireUnconsumed = false) } }
    ) {
        Box(Modifier.fillMaxSize().safeDrawingPadding()) {
            BoxWithConstraints(Modifier.fillMaxSize()) {
                spiel.breite = maxWidth.value
                spiel.hoehe = maxHeight.value
                Canvas(
                    Modifier
                        .fillMaxSize()
                        .pointerInput(Unit) { detectTapGestures { spiel.starten() } }
                ) {
                    @Suppress("UNUSED_VARIABLE") val n = bildNr
                    inDp { zeichnen(spiel, farbe) }
                    spiel.bonus?.let { b ->
                        val t = messer.measure(b.text, TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 17.sp, color = farbe))
                        drawText(t, topLeft = Offset(b.ort.x * density - t.size.width / 2, b.ort.y * density - t.size.height / 2))
                    }
                }
            }
            // Punkte und Rekord oben
            Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 76.dp, top = 14.dp)) {
                Text("%05d".format(punkte), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                Spacer(Modifier.weight(1f))
                Text("Rekord " + "%05d".format(spiel.rekord), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 17.sp, color = zweitrangig)
            }
            // Start- und Endtafel
            when (phase) {
                Wollalarm.Phase.start -> Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text("Wollalarm", fontSize = 44.sp, fontWeight = FontWeight.Black)
                    Text("Wippe: fahren · Dampf: pusten", color = zweitrangig)
                    Text("Tippen zum Start", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 20.dp))
                }
                Wollalarm.Phase.ende -> Column(
                    Modifier.align(Alignment.Center).background(MaterialTheme.colorScheme.background.copy(alpha = 0.9f), RoundedCornerShape(22.dp)).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Ende", fontSize = 44.sp, fontWeight = FontWeight.Black)
                    Text("${spiel.punkte} Punkte", fontSize = 20.sp)
                    if (spiel.punkte > 0 && spiel.punkte == spiel.rekord) Text("Neuer Rekord!", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text("Tippen für ein neues Spiel", color = zweitrangig, modifier = Modifier.padding(top = 16.dp))
                }
                Wollalarm.Phase.laeuft -> Unit
            }
            // Unten: die Wippe zum Fahren, rechts die Dampftaste.
            Row(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(start = 22.dp, end = 22.dp, bottom = 30.dp), verticalAlignment = Alignment.CenterVertically) {
                Wippe { spiel.steuer = it }
                Spacer(Modifier.weight(1f))
                Dampftaste { spiel.dampf(it) }
            }
            Box(
                Modifier.align(Alignment.TopEnd).padding(end = 16.dp, top = 4.dp).size(44.dp).glas(CircleShape)
                    .clickable(remember { MutableInteractionSource() }, null, onClick = schliessen),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.Close, "Schließen") }
        }
    }
}

private fun DrawScope.zeichnen(s: Wollalarm, farbe: Color) {
    val str = strich(1.8f)
    // Boden
    drawLine(farbe, Offset(0f, s.lokY + 6), Offset(s.breite, s.lokY + 6), 1.2f)

    // Prellböcke
    for (p in s.prellboecke) {
        val steine = Path()
        for (r in 0 until 9) for (c in 0 until 14) if (p.zellen[r][c]) {
            steine.rechteck(p.x + c * Wollalarm.ZELLE, p.y + r * Wollalarm.ZELLE, Wollalarm.ZELLE, Wollalarm.ZELLE)
        }
        drawPath(steine, farbe)
    }

    // Katzen
    for (k in s.katzen) if (k.lebt) katze(s.ort(k), k.reihe, s.bild, farbe)

    // Kontrolleur
    s.kontrolleur?.let { kontrolleur(it, farbe) }

    // Lok (blinkt nach einem Treffer)
    val blinkt = s.zeit < s.unverwundbarBis && (s.zeit * 10).toInt() % 2 == 0
    if (s.phase != Wollalarm.Phase.start && !blinkt) {
        verschoben(s.lokX, s.lokY) { skaliert(0.7f) { verschoben(-37f, -54f) { with(LokZeichnung) { koerper(farbe, s.lokWeg) } } } }
    }

    // Leben oben links unter den Punkten
    for (i in 0 until max(0, s.leben - 1)) {
        verschoben(34f + i * 34, 62f) { skaliert(0.38f) { verschoben(-37f, -54f) { with(LokZeichnung) { koerper(farbe, 0.0) } } } }
    }

    // Dampfwolken
    for (d in s.schuesse) {
        val w = Path()
        w.oval(d.x - 4, d.y - 5, 8f, 8f)
        w.oval(d.x - 6, d.y - 1, 6f, 6f)
        w.oval(d.x + 1, d.y, 5f, 5f)
        drawPath(w, farbe, style = Stroke(1.4f))
    }

    // Wollknäuel
    for (k in s.knaeuel) {
        val w = Path()
        w.oval(k.x - 4.5f, k.y - 4.5f, 9f, 9f)
        val dreh = k.y / 6.0
        w.moveTo(k.x + cos(dreh).toFloat() * 4, k.y + sin(dreh).toFloat() * 4)
        w.bogen(k.x - cos(dreh).toFloat() * 4, k.y - sin(dreh).toFloat() * 4, k.x + sin(dreh).toFloat() * 3, k.y - cos(dreh).toFloat() * 3)
        // Losgelöster Faden
        w.moveTo(k.x, k.y - 4.5f)
        w.bogen(k.x + 3, k.y - 12, k.x - 4, k.y - 9)
        drawPath(w, farbe, style = strich(1.3f))
    }

    // Treffer
    for (b in s.blitze) {
        val f = ((s.zeit - b.zeit) / 0.35).toFloat()
        val r = 4 + f * (if (b.gross) 22 else 12)
        val stern = Path()
        for (i in 0 until 8) {
            val w = i * Math.PI / 4
            stern.linie(b.ort.x + cos(w).toFloat() * r * 0.4f, b.ort.y + sin(w).toFloat() * r * 0.4f, b.ort.x + cos(w).toFloat() * r, b.ort.y + sin(w).toFloat() * r)
        }
        drawPath(stern, farbe.copy(alpha = (1 - f).coerceIn(0f, 1f)), style = str)
    }
}

/** Kleine struppige Katze von vorn, zwei Bilder im Wechsel (Ohren und Maul). */
private fun DrawScope.katze(p: Offset, reihe: Int, bild: Boolean, farbe: Color) {
    val g = if (reihe == 0) 8.5f else if (reihe < 3) 9.5f else 10.5f
    val kopf = Path()
    val n = 14
    for (i in 0 until n) {
        val w = i.toDouble() / n * 2 * Math.PI
        val rr = if (i % 2 == 0) g else g * 0.82f
        val x = p.x + cos(w).toFloat() * rr
        val y = p.y + sin(w).toFloat() * rr
        if (i == 0) kopf.moveTo(x, y) else kopf.lineTo(x, y)
    }
    kopf.close()
    // Ohren, im Wechsel gekippt
    val kipp = if (bild) 2f else -2f
    val ohren = Path()
    for (s in listOf(-1f, 1f)) {
        ohren.moveTo(p.x + s * g * 0.35f, p.y - g * 0.75f)
        ohren.lineTo(p.x + s * g * 0.95f + kipp, p.y - g * 1.45f)
        ohren.lineTo(p.x + s * g * 0.9f, p.y - g * 0.4f)
    }
    drawPath(ohren, farbe, style = strich(1.8f))
    drawPath(kopf, farbe, style = strich(1.8f))
    // Große Augen
    val augen = Path()
    val pupillen = Path()
    for (s in listOf(-1f, 1f)) {
        augen.oval(p.x + s * g * 0.38f - g * 0.3f, p.y - g * 0.35f, g * 0.6f, g * 0.65f)
        pupillen.oval(p.x + s * g * 0.38f - 1.3f, p.y - g * 0.05f, 2.6f, 2.6f)
    }
    drawPath(augen, farbe, style = Stroke(1.3f))
    drawPath(pupillen, farbe)
    // Maul auf, Maul zu
    val maul = Path()
    if (bild) maul.oval(p.x - 2, p.y + g * 0.4f, 4f, 3.5f) else maul.linie(p.x - 2.5f, p.y + g * 0.5f, p.x + 2.5f, p.y + g * 0.5f)
    drawPath(maul, farbe, style = strich(1.2f))
}

/** Kopf eines Kontrolleurs mit Mütze und Schnauzbart. */
private fun DrawScope.kontrolleur(p: Offset, farbe: Color) {
    val k = Path()
    k.oval(p.x - 10, p.y - 8, 20f, 20f)
    // Mütze mit Schirm
    k.rund(p.x - 11, p.y - 16, 22f, 9f, 3f)
    k.linie(p.x - 14, p.y - 7, p.x + 14, p.y - 7)
    // Augen und Schnauzbart
    k.oval(p.x - 5, p.y - 2, 2.5f, 2.5f)
    k.oval(p.x + 2.5f, p.y - 2, 2.5f, 2.5f)
    k.moveTo(p.x - 7, p.y + 6)
    k.bogen(p.x, p.y + 4, p.x - 4, p.y + 2)
    k.bogen(p.x + 7, p.y + 6, p.x + 4, p.y + 2)
    drawPath(k, farbe, style = strich(1.8f))
}

/**
 * Wippe zum Fahren: Je weiter außen der Finger, desto schneller; in der Mitte steht die Lok.
 * Man kann darüber gleiten, ohne loszulassen. Sie neigt sich zur gedrückten Seite.
 */
@Composable
private fun Wippe(steuer: (Float) -> Unit) {
    var wert by remember { mutableFloatStateOf(0f) }
    val neigung by animateFloatAsState(wert * 14f, label = "wippe")
    val breite = 220f
    Row(
        Modifier
            .size(breite.dp, 72.dp)
            .graphicsLayer(rotationY = neigung, cameraDistance = 12f)
            .glas(RoundedCornerShape(50))
            .pointerInput(Unit) {
                awaitEachGesture {
                    val unten = awaitFirstDown()
                    fun setzen(x: Float) {
                        val mitte = size.width / 2f
                        val anteil = ((x - mitte) / (mitte - 18.dp.toPx())).coerceIn(-1f, 1f)
                        // Kleiner ruhiger Bereich in der Mitte, außen spürbar schneller
                        val betrag = max(0f, (abs(anteil) - 0.12f) / 0.88f)
                        wert = (if (anteil < 0) -1f else 1f) * betrag.pow(1.3f)
                        steuer(wert)
                    }
                    setzen(unten.position.x)
                    var id = unten.id
                    while (true) {
                        val e = awaitPointerEvent()
                        val c = e.changes.firstOrNull { it.id == id } ?: e.changes.first().also { id = it.id }
                        if (!c.pressed) break
                        if (c.positionChange() != Offset.Zero) setzen(c.position.x)
                        c.consume()
                    }
                    wert = 0f
                    steuer(0f)
                }
            }
            .padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.AutoMirrored.Filled.ArrowLeft, null, modifier = Modifier.size(36.dp).alpha(if (wert < 0) 1f else 0.45f))
        Spacer(Modifier.weight(1f))
        Box(Modifier.size(6.dp).alpha(0.3f).background(MaterialTheme.colorScheme.onBackground, CircleShape))
        Spacer(Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Filled.ArrowRight, null, modifier = Modifier.size(36.dp).alpha(if (wert > 0) 1f else 0.45f))
    }
}

/** Dampftaste: schießt beim Herunterdrücken; gehalten pustet sie fortlaufend. */
@Composable
private fun Dampftaste(gedrueckt: (Boolean) -> Unit) {
    var unten by remember { mutableStateOf(false) }
    val groesse by animateFloatAsState(if (unten) 0.88f else 1f, label = "dampf")
    Box(
        Modifier
            .size(80.dp)
            .scale(groesse)
            .glas(CircleShape)
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown().consume()
                    unten = true
                    gedrueckt(true)
                    while (true) {
                        val e = awaitPointerEvent()
                        e.changes.forEach { it.consume() }
                        if (e.changes.none { it.pressed }) break
                    }
                    unten = false
                    gedrueckt(false)
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.Cloud, "Dampf", modifier = Modifier.size(34.dp))
    }
}
