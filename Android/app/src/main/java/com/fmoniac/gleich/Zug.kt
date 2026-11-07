package com.fmoniac.gleich

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.random.Random

/**
 * Kleiner Strichzug auf einem runden Gleis: vorne die Lok, dahinter vier Wagen. Er fährt im Kreis – sanft anlaufen,
 * ein, zwei Runden, auslaufen – und bleibt jedes Mal an einer anderen Stelle stehen. Beim Fahren stößt die Lok
 * Wölkchen aus. Ein Tipp lässt ihn noch einmal kurz fahren. Steht in der Suche, solange dort noch nichts zu sehen ist.
 */
@Composable
fun ZugImKreis(rauch: Rauch, modifier: Modifier = Modifier) {
    val farbe = MaterialTheme.colorScheme.onBackground
    val papier = MaterialTheme.colorScheme.background
    val dichte = LocalDensity.current.density
    val bereich = rememberCoroutineScope()

    var rahmen by remember { mutableStateOf(Rect.Zero) }
    var basis by remember { mutableDoubleStateOf(Random.nextDouble(0.0, 2 * Math.PI)) }
    var strecke by remember { mutableDoubleStateOf(0.0) }
    var start by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var dauer by remember { mutableDoubleStateOf(4.0) }
    var laeuft by remember { mutableStateOf(false) }
    var lauf by remember { mutableIntStateOf(0) }
    var jetzt by remember { mutableLongStateOf(System.currentTimeMillis()) }

    fun fortschritt(t: Long) = min(1.0, (t - start) / 1000.0 / dauer)

    /** Wo der Schornstein gerade ist, in Fenster-Bildpunkten. */
    fun schornstein(winkel: Double): Offset {
        // Schornsteinöffnung der Lok liegt bei (58, 16,5); verschoben, gedreht und verkleinert wie unten.
        val lx = (R + (54 - 16.5f) * MASSSTAB) * dichte
        val ly = ((58 - 37) * MASSSTAB) * dichte
        val c = rahmen.center
        return Offset(
            c.x + lx * cos(winkel).toFloat() - ly * sin(winkel).toFloat(),
            c.y + lx * sin(winkel).toFloat() + ly * cos(winkel).toFloat(),
        )
    }

    /** Neue Fahrt ab der Stelle, an der er gerade ist; Länge zufällig, damit er woanders stehen bleibt. */
    fun losfahren(kurz: Boolean) {
        basis += if (laeuft) strecke * sanft(fortschritt(System.currentTimeMillis())) else strecke
        strecke = 2 * Math.PI * (if (kurz) Random.nextDouble(0.8, 1.5) else Random.nextDouble(1.4, 2.4))
        dauer = if (kurz) 2.6 else 4.2
        start = System.currentTimeMillis()
        laeuft = true
        lauf += 1
        val meiner = lauf
        bereich.launch {
            delay(((dauer + 0.1) * 1000).toLong())
            if (lauf == meiner) laeuft = false
        }
        // Wölkchen, solange er in Fahrt ist
        bereich.launch {
            delay(500)
            while (lauf == meiner && laeuft) {
                val p = fortschritt(System.currentTimeMillis())
                if (tempo(p) > 0.15) rauch.ausstossen(schornstein(basis + strecke * sanft(p)), rahmen.center)
                delay(380)
            }
        }
    }

    LaunchedEffect(Unit) { losfahren(kurz = false) }
    // Verschwindet er (es wird gesucht), hört auch der Dampf sofort auf.
    DisposableEffect(Unit) { onDispose { lauf += 1; laeuft = false } }
    LaunchedEffect(laeuft) {
        while (laeuft) withFrameMillis { jetzt = System.currentTimeMillis() }
    }

    Canvas(
        modifier
            .size(250.dp)
            .onGloballyPositioned { rahmen = it.boundsInRoot() }
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                losfahren(kurz = true)
            }
    ) {
        val p = if (laeuft) fortschritt(jetzt) else 1.0
        val winkel = basis + strecke * sanft(p)
        inDp { zeichnen(winkel, farbe, papier) }
    }
}

private const val R = 60f
private const val MASSSTAB = 0.86f
private const val WAGEN = 4
/** Länge eines Wagens samt Puffern (in Lok-Maßen) und Abstand dazwischen. */
private const val WAGEN_LAENGE = 44f
private const val KUPPLUNG = 3f

/** Langsam anlaufen, langsam auslaufen. */
private fun sanft(p: Double) = if (p < 0.5) 4 * p * p * p else 1 - (-2 * p + 2).pow(3) / 2

/** Momentane Geschwindigkeit der Fahrt, 0 bis 1. */
private fun tempo(p: Double) = (if (p < 0.5) 12 * p * p else 3 * (-2 * p + 2).pow(2)) / 3

private fun DrawScope.zeichnen(winkel: Double, farbe: Color, papier: Color) {
    // Räder drehen sich mit dem zurückgelegten Weg – so werden sie mit dem Zug langsamer.
    val rad = winkel * 18
    verschoben(125f, 125f) {
        gleis(farbe)
        gedreht(Math.toDegrees(winkel).toFloat()) {
            // Wagen von hinten nach vorn, jeweils als Sehne auf dem Kreis, damit beide Achsen auf dem Gleis stehen.
            // Die Lok fährt in Richtung wachsender Winkel; die Wagen hängen dahinter.
            val lokHinten = 34 * MASSSTAB
            val l = WAGEN_LAENGE * MASSSTAB
            for (i in WAGEN - 1 downTo 0) {
                val abstand = lokHinten + KUPPLUNG + l / 2 + i * (l + KUPPLUNG)
                val mitte = -(abstand / R).toDouble()
                val halb = asin((l / 2 / R).toDouble())
                gedreht(Math.toDegrees(mitte).toFloat()) {
                    verschoben(R * cos(halb).toFloat(), 0f) {
                        skaliert(MASSSTAB) {
                            gedreht(90f) {
                                verschoben(-WAGEN_LAENGE / 2, -54.5f) { wagen(rad, farbe, papier) }
                            }
                        }
                    }
                }
            }
            // Dieselbe Lok wie beim Herunterziehen. Räder auf dem Gleis, Schornstein außen.
            verschoben(R, 0f) {
                skaliert(MASSSTAB) {
                    gedreht(90f) {
                        verschoben(-37f, -54f) {
                            val hinten = Path()
                            hinten.rechteck(10f, 18f, 20f, 24f)
                            hinten.rund(30f, 28f, 34f, 14f, 7f)
                            drawPath(hinten, papier)
                            with(LokZeichnung) { koerper(farbe, rad) }
                        }
                    }
                }
            }
        }
    }
}

/** Ein schmales rundes Gleis mit kurzen Schwellen nach innen. */
private fun DrawScope.gleis(farbe: Color) {
    val g = Path()
    g.oval(-R, -R, 2 * R, 2 * R)
    for (i in 0 until 36) {
        val w = i / 36.0 * 2 * Math.PI
        g.linie((cos(w) * R).toFloat(), (sin(w) * R).toFloat(), (cos(w) * (R - 5)).toFloat(), (sin(w) * (R - 5)).toFloat())
    }
    drawPath(g, farbe.copy(alpha = 0.5f), style = strich(1.2f))
}

/** Ein Personenwagen im Stil der Lok: fährt nach rechts (+x), Dach oben (−y), Räder unten bei y ≈ 54,5. */
private fun DrawScope.wagen(winkel: Double, farbe: Color, papier: Color) {
    val kasten = Path()
    kasten.rund(4f, 24f, 36f, 18f, 2f)
    drawPath(kasten, papier)

    val p = Path()
    p.rund(4f, 24f, 36f, 18f, 2f)
    // Gewölbtes Dach mit kleinem Überstand
    p.moveTo(2f, 24f); p.bogen(42f, 24f, 22f, 16f)
    // Drei Fenster
    for (x in listOf(8f, 19f, 30f)) p.rund(x, 28f, 7f, 7f, 1.5f)
    // Rahmen und Puffer vorn und hinten
    p.linie(3f, 42f, 41f, 42f)
    p.linie(0f, 39f, 4f, 39f)
    p.linie(40f, 39f, 44f, 39f)
    drawPath(p, farbe, style = strich(1.8f))

    // Zwei Räder mit Speichen
    val r = Path()
    for (mx in listOf(11f, 33f)) {
        val my = 48.5f
        val radius = 6f
        r.oval(mx - radius, my - radius, radius * 2, radius * 2)
        for (i in 0 until 3) {
            val w = winkel + i * Math.PI / 3
            val dx = (cos(w) * radius * 0.8).toFloat()
            val dy = (sin(w) * radius * 0.8).toFloat()
            r.linie(mx - dx, my - dy, mx + dx, my + dy)
        }
    }
    drawPath(r, papier)
    drawPath(r, farbe, style = strich(1.3f))
}
