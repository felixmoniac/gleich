package com.fmoniac.gleich

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseIn
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.first
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.layout.layout
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.pulltorefresh.pullToRefresh
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// ---------- Zeichenhelfer: gezeichnet wird in dp, wie auf dem iPhone in Punkten ----------

/** Zeichnet in dp statt in Bildpunkten – die Maße stammen aus der iPhone-Fassung. */
inline fun DrawScope.inDp(block: DrawScope.() -> Unit) {
    val d = density
    withTransform({ scale(d, d, pivot = Offset.Zero) }, block)
}

inline fun DrawScope.verschoben(x: Float, y: Float, block: DrawScope.() -> Unit) =
    withTransform({ translate(x, y) }, block)

inline fun DrawScope.gedreht(grad: Float, block: DrawScope.() -> Unit) =
    withTransform({ rotate(grad, pivot = Offset.Zero) }, block)

inline fun DrawScope.skaliert(f: Float, block: DrawScope.() -> Unit) =
    withTransform({ scale(f, f, pivot = Offset.Zero) }, block)

fun strich(breite: Float) = Stroke(width = breite, cap = StrokeCap.Round, join = StrokeJoin.Round)

fun Path.oval(x: Float, y: Float, b: Float, h: Float) = addOval(Rect(x, y, x + b, y + h))
fun Path.rechteck(x: Float, y: Float, b: Float, h: Float) = addRect(Rect(x, y, x + b, y + h))
fun Path.rund(x: Float, y: Float, b: Float, h: Float, r: Float) =
    addRoundRect(RoundRect(Rect(x, y, x + b, y + h), CornerRadius(r, r)))
fun Path.linie(x1: Float, y1: Float, x2: Float, y2: Float) { moveTo(x1, y1); lineTo(x2, y2) }
@Suppress("DEPRECATION")
fun Path.bogen(x: Float, y: Float, kx: Float, ky: Float) = quadraticBezierTo(kx, ky, x, y)

/** Sekunden seit dem Start, laufend aktualisiert, solange `laeuft`. */
@Composable
fun rememberUhr(laeuft: Boolean = true): State<Double> {
    val t = remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(laeuft) {
        if (!laeuft) return@LaunchedEffect
        val start = withFrameNanos { it }
        while (true) {
            withFrameNanos { t.doubleValue = (it - start) / 1e9 }
        }
    }
    return t
}

// ---------- Die Lok ----------

object LokZeichnung {
    const val BREITE = 76f
    const val HOEHE = 74f

    val DICK = strich(1.8f)
    val DUENN = strich(1.3f)
    private val STANGE = strich(2f)

    /** Alles, was sich nicht bewegt – einmal gebaut, dann immer wieder gezeichnet. */
    private val rahmen: Path by lazy {
        val p = Path()
        // Kessel mit runder Rauchkammer vorne
        p.rund(30f, 28f, 34f, 14f, 7f)
        // Führerhaus mit Fenster und überstehendem Dach
        p.rechteck(10f, 18f, 20f, 24f)
        p.rund(15f, 22f, 10f, 8f, 2f)
        p.moveTo(6f, 18f); p.bogen(34f, 18f, 20f, 12f)
        // Schornstein als Trichter
        p.linie(55f, 28f, 53f, 17f)
        p.linie(61f, 28f, 63f, 17f)
        p.linie(51.5f, 16.5f, 64.5f, 16.5f)
        // Dom
        p.moveTo(38f, 28f); p.bogen(46f, 28f, 42f, 20f)
        // Rahmen, Puffer, Schienenräumer
        p.linie(7f, 42f, 66f, 42f)
        p.linie(3f, 39f, 7f, 39f)
        p.moveTo(64f, 42f); p.lineTo(71f, 51f); p.lineTo(62f, 51f)
        p
    }
    private val RAEDER = listOf(Triple(21f, 46f, 8.5f), Triple(42f, 48.5f, 6f), Triple(56f, 48.5f, 6f))
    private val radkreise: Path by lazy {
        val r = Path()
        for ((mx, my, radius) in RAEDER) r.oval(mx - radius, my - radius, radius * 2, radius * 2)
        r
    }

    /** Die Lok selbst, ohne Dampf: fährt nach rechts (+x), Schornstein oben (−y), Räder unten bei y ≈ 54. */
    fun DrawScope.koerper(farbe: Color, winkel: Double) {
        drawPath(rahmen, farbe, style = DICK)
        // Räder mit Speichen und Kuppelstange
        drawPath(radkreise, farbe, style = DUENN)
        val r = Path()
        for ((mx, my, radius) in RAEDER) speichen(r, mx, my, radius, winkel)
        drawPath(r, farbe, style = DUENN)
        val kx = (cos(winkel) * 3.5).toFloat()
        val ky = (sin(winkel) * 3.5).toFloat()
        val stange = Path()
        stange.moveTo(21 + kx * 1.3f, 46 + ky * 1.3f)
        stange.lineTo(42 + kx, 48.5f + ky)
        stange.lineTo(56 + kx, 48.5f + ky)
        drawPath(stange, farbe, style = STANGE)
    }

    /** Drei Speichen eines Rads, gedreht um `winkel`. */
    fun speichen(r: Path, mx: Float, my: Float, radius: Float, winkel: Double) {
        for (i in 0 until 3) {
            val w = winkel + i * Math.PI / 3
            val dx = (cos(w) * radius * 0.8).toFloat()
            val dy = (sin(w) * radius * 0.8).toFloat()
            r.linie(mx - dx, my - dy, mx + dx, my + dy)
        }
    }

    private val WOLKE = Stroke(1.3f)

    fun DrawScope.dampf(farbe: Color, t: Double, hupf: Double) {
        for (i in 0 until 4) {
            val phase = ((t * 1.4 + i / 4.0) % 1.0)
            val x = (58 - phase * 34 + sin(phase * 9 + i) * 2).toFloat()
            val y = (14 + hupf * (1 - phase) - phase * 15).toFloat()
            val r = (2.5 + phase * 6.5).toFloat()
            val w = Path()
            // Drei überlappende Kreise ergeben eine Wolke.
            w.oval(x - r, y - r * 0.8f, r * 2, r * 1.6f)
            w.oval(x - r * 1.6f, y - r * 0.3f, r * 1.3f, r * 1.1f)
            w.oval(x + r * 0.4f, y - r * 0.2f, r * 1.2f, r)
            drawPath(w, farbe.copy(alpha = ((1 - phase) * 0.85).toFloat()), style = WOLKE)
        }
    }
}

/**
 * Kleine Dampflok in Strichoptik. Fährt nach rechts.
 * `ruckelt`: tuckert auf der Stelle (hüpft, wackelt, dampft).
 * `strecke`: zurückgelegter Weg in dp – dreht die Räder beim Hereinrollen. Wird erst beim Zeichnen gelesen,
 * damit sich beim Ziehen nur das Bild erneuert und nicht die ganze Seite.
 */
@Composable
fun Lok(ruckelt: Boolean, modifier: Modifier = Modifier, strecke: () -> Float = { 0f }) {
    val farbe = MaterialTheme.colorScheme.onBackground
    val uhr = rememberUhr(ruckelt)
    Canvas(modifier.size(LokZeichnung.BREITE.dp, LokZeichnung.HOEHE.dp)) {
        val t = if (ruckelt) uhr.value else 0.0
        inDp {
            // Oben Platz für den Dampf lassen.
            verschoben(0f, 16f) {
                // Huckeln, Buckeln, Ruckeln – absichtlich unregelmäßig.
                val hupf = if (ruckelt) -abs(sin(t * 11)) * 2.2 - max(0.0, sin(t * 3.7)) * 1.2 else 0.0
                val kipp = if (ruckelt) sin(t * 6.5) * 0.05 + sin(t * 15.3) * 0.015 else 0.0
                val ruck = if (ruckelt) sin(t * 17) * 0.6 else 0.0
                val winkel = if (ruckelt) t * 9 else strecke() / 7.0
                with(LokZeichnung) {
                    if (ruckelt) dampf(farbe, t, hupf)
                    verschoben((38 + ruck).toFloat(), (50 + hupf).toFloat()) {
                        gedreht(Math.toDegrees(kipp).toFloat()) {
                            verschoben(-38f, -50f) { koerper(farbe, winkel) }
                        }
                    }
                }
            }
        }
    }
}

private enum class LokPhase { ruhe, laden, abfahrt }

/**
 * Scrollbereich mit eigenem „Runterziehen zum Aktualisieren“: Statt eines Kreisels rollt die Lok herein,
 * tuckert, solange geladen wird, und dampft danach rechts davon.
 * `unten`: Inhalt unten bündig – kurze Listen enden am unteren Rand statt oben zu kleben.
 *
 * Sparsam: Alles, was sich bei jedem Bild ändert (Ziehweg, Abfahrt), wird erst beim Anordnen oder Zeichnen gelesen –
 * so baut Android dabei nicht die ganze Seite neu auf, sondern verschiebt und malt nur die Lok.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LokScroll(
    laedt: Boolean,
    modifier: Modifier = Modifier,
    unten: Boolean = false,
    aktualisieren: suspend () -> Unit,
    inhalt: @Composable ColumnScope.() -> Unit,
) {
    val zustand = rememberPullToRefreshState()
    val bereich = rememberCoroutineScope()
    // Immer der neueste Stand – auch in Abläufen, die schon vor einer Weile gestartet sind.
    val laedtJetzt by rememberUpdatedState(laedt)
    var phase by remember { mutableStateOf(LokPhase.ruhe) }
    var start by remember { mutableLongStateOf(0L) }
    val weg = remember { Animatable(0f) }
    val breite = remember { floatArrayOf(400f) }
    // Nach der Abfahrt gleitet die Ziehanzeige von selbst zurück. Dabei darf die Lok nicht
    // noch einmal auftauchen und nach links aus dem Bild rollen.
    var verborgen by remember { mutableStateOf(false) }
    val zieht by remember { derivedStateOf { zustand.distanceFraction > 0.005f } }

    fun abfahren() {
        if (phase != LokPhase.laden) return
        bereich.launch {
            // Die Lok soll man wenigstens kurz tuckern sehen.
            val rest = max(0L, 900 - (System.currentTimeMillis() - start))
            delay(rest)
            if (phase != LokPhase.laden || laedtJetzt) return@launch
            phase = LokPhase.abfahrt
            weg.animateTo(breite[0] / 2 + 60, tween(750, easing = EaseIn))
            verborgen = true
            phase = LokPhase.ruhe
            weg.snapTo(0f)
            withTimeoutOrNull(2000) { snapshotFlow { zustand.distanceFraction }.first { it <= 0f } }
            verborgen = false
        }
    }

    LaunchedEffect(laedt) {
        if (laedt && phase == LokPhase.ruhe) {
            weg.snapTo(0f)
            start = System.currentTimeMillis()
            phase = LokPhase.laden
        } else if (!laedt && phase == LokPhase.laden) {
            abfahren()
        }
    }

    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .pullToRefresh(
                isRefreshing = phase != LokPhase.ruhe,
                state = zustand,
                threshold = 100.dp,
                onRefresh = {
                    bereich.launch {
                        weg.snapTo(0f)
                        start = System.currentTimeMillis()
                        verborgen = false
                        phase = LokPhase.laden
                        aktualisieren()
                        if (!laedtJetzt) abfahren()
                    }
                },
            )
    ) {
        breite[0] = maxWidth.value
        val hoehe = maxHeight
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .heightIn(min = if (unten) hoehe else 0.dp),
            verticalArrangement = if (unten) Arrangement.Bottom else Arrangement.Top,
        ) {
            if (phase != LokPhase.ruhe) {
                Box(Modifier.fillMaxWidth().height(84.dp), contentAlignment = Alignment.Center) {
                    Lok(ruckelt = true, modifier = Modifier.offset { IntOffset(weg.value.dp.roundToPx(), 0) })
                }
            } else if (zieht) {
                // Beim Ziehen rollt die Lok von links herein – erst, wenn die Lücke groß genug für die ganze Lok ist.
                fun zug() = zustand.distanceFraction * 100f
                fun x(): Float {
                    val anteil = ((zug() - 52f) / (100f - 52f)).coerceIn(0f, 1f)
                    return -(breite[0] / 2 + 50) * (1 - anteil)
                }
                Box(
                    Modifier
                        .fillMaxWidth()
                        .layout { messbar, grenzen ->
                            // Nach der Abfahrt schließt sich die Lücke ohne Sprung aus der Ladehöhe heraus.
                            val h = (if (verborgen) min(zug(), 84f) else zug()).dp.roundToPx()
                            val teil = messbar.measure(Constraints.fixed(grenzen.maxWidth, h))
                            layout(grenzen.maxWidth, h) { teil.place(0, 0) }
                        }
                        .clipToBounds(),
                    contentAlignment = Alignment.BottomCenter,
                ) {
                    if (!verborgen) {
                        Lok(ruckelt = false, strecke = ::x, modifier = Modifier.offset { IntOffset(x().dp.roundToPx(), 0) })
                    }
                }
            }
            inhalt()
        }
    }
}
