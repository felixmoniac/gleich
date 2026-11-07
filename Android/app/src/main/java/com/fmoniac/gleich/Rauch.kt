package com.fmoniac.gleich

import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.State
import androidx.compose.runtime.key
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.UUID
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Rauchwolken der kleinen Lok: Sie wachsen, verlassen den Kreis und ziehen über den Bildschirm.
 * Nur eine Wolke trägt einen Zen-Spruch. Wer sie antippt, bekommt ihn – und alle anderen zerplatzen.
 * Andere Wolken zerplatzen beim Antippen einfach. Wolken und Sprüche verblassen von selbst.
 * Alle Orte in dp, gemessen von der linken oberen Ecke der Fläche, über der die Wolken liegen.
 */
class Rauch {
    /** Zufällige Gestalt einer Wolke: Beulen, Dellen, Streckung. */
    class Form {
        val buckel = Random.nextInt(5, 10)
        val verzug = Random.nextDouble(0.15, 0.5)
        val dreh = Random.nextDouble(0.0, 2 * Math.PI)
        val a2 = Random.nextDouble(0.05, 0.14)
        val a3 = Random.nextDouble(0.03, 0.10)
        val p1 = Random.nextDouble(0.0, 2 * Math.PI)
        val p2 = Random.nextDouble(0.0, 2 * Math.PI)
        val p3 = Random.nextDouble(0.0, 2 * Math.PI)
        val streck = Random.nextDouble(0.8, 1.25)
    }

    class Ring(
        val start: Offset,
        val richtung: Offset,
        val tempo: Float,
        val wackel: Double,
        val traegtSpruch: Boolean,
    ) {
        val id: String = UUID.randomUUID().toString()
        val form = Form()
        val geburt = System.currentTimeMillis()
    }

    /** Eine Wolke, die gerade zerplatzt. */
    class Platzer(val ort: Offset, val radius: Float, val form: Form) {
        val fetzen = List(7) { Random.nextDouble(0.0, 2 * Math.PI) }
        val geburt = System.currentTimeMillis()
    }

    class Spruch(val text: String, val ort: Offset) {
        val geburt = System.currentTimeMillis()
    }

    val ringe = mutableStateListOf<Ring>()
    val platzer = mutableStateListOf<Platzer>()
    val sprueche = mutableStateListOf<Spruch>()
    /** Während gesucht wird, kommt kein neuer Rauch. */
    var ruht = false
    /** So viele Wolken noch, bis wieder eine den Spruch trägt. */
    private var bisSpruch = Random.nextInt(1, 4)

    /** Wo die Fläche liegt (Bildpunkte im Fenster) – zum Umrechnen der Schornsteinposition. */
    var flaeche = Offset.Zero
    var dichte = 1f

    val istLeer: Boolean get() = ringe.isEmpty() && sprueche.isEmpty() && platzer.isEmpty()

    /** Neue Wolke am Schornstein, fliegt grob von der Kreismitte weg. Beide Punkte in Fenster-Bildpunkten. */
    fun ausstossen(beiPx: Offset, wegPx: Offset) {
        if (ruht) return
        val ort = (beiPx - flaeche) / dichte
        val mitte = (wegPx - flaeche) / dichte
        var dx = ort.x - mitte.x
        var dy = ort.y - mitte.y
        val laenge = max(1f, sqrt(dx * dx + dy * dy))
        dx /= laenge; dy /= laenge
        // Etwas streuen, und leicht nach oben treiben lassen, wie Rauch eben
        val streu = Random.nextDouble(-0.6, 0.6)
        val rx = dx * cos(streu).toFloat() - dy * sin(streu).toFloat()
        val ry = dx * sin(streu).toFloat() + dy * cos(streu).toFloat() - 0.35f
        // Immer nur eine Wolke mit Spruch unterwegs
        var traegt = false
        if (sprueche.isEmpty() && ringe.none { it.traegtSpruch }) {
            if (bisSpruch <= 0) {
                traegt = true
                bisSpruch = Random.nextInt(2, 6)
            } else {
                bisSpruch -= 1
            }
        }
        ringe += Ring(ort, Offset(rx, ry), Random.nextDouble(34.0, 62.0).toFloat(),
            Random.nextDouble(0.0, 2 * Math.PI), traegt)
    }

    /** Die Spruch-Wolke gibt ihren Spruch frei und alle zerplatzen; jede andere zerplatzt allein. */
    fun antippen(ring: Ring) {
        val jetzt = System.currentTimeMillis()
        val betroffen = if (ring.traegtSpruch) ringe.toList() else listOf(ring)
        for (r in betroffen) {
            val z = zustand(r, jetzt)
            platzer += Platzer(z.ort, z.radius, r.form)
        }
        val weg = betroffen.map { it.id }.toSet()
        ringe.removeAll { it.id in weg }
        if (ring.traegtSpruch) sprueche += Spruch(Zen.naechster(), zustand(ring, jetzt).ort)
    }

    /** Welche Wolke liegt an diesem Punkt (dp)? */
    fun getroffen(p: Offset, jetzt: Long): Ring? = ringe.lastOrNull { r ->
        val z = zustand(r, jetzt)
        (z.ort - p).getDistance() <= z.radius * 1.2f
    }

    fun aufraeumen(jetzt: Long) {
        ringe.removeAll { jetzt - it.geburt > RING_DAUER * 1000 }
        platzer.removeAll { jetzt - it.geburt > PLATZ_DAUER * 1000 }
        sprueche.removeAll { jetzt - it.geburt > SPRUCH_DAUER * 1000 }
    }

    fun leeren() {
        ringe.clear()
        platzer.clear()
        sprueche.clear()
    }

    data class Zustand(val ort: Offset, val radius: Float, val deckkraft: Float)

    companion object {
        const val RING_DAUER = 9.0
        const val SPRUCH_DAUER = 6.0
        const val PLATZ_DAUER = 0.45

        /** Wo eine Wolke gerade ist, wie groß und wie sichtbar. */
        fun zustand(ring: Ring, jetzt: Long): Zustand {
            val a = (jetzt - ring.geburt) / 1000.0
            val f = min(1.0, a / RING_DAUER)
            // Erst flott, dann gemächlich
            val weg = (ring.tempo * a * (1 - f * 0.45)).toFloat()
            val quer = (sin(a * 1.3 + ring.wackel) * 10).toFloat()
            val ort = Offset(
                ring.start.x + ring.richtung.x * weg - ring.richtung.y * quer,
                ring.start.y + ring.richtung.y * weg + ring.richtung.x * quer,
            )
            val radius = (4 + 46 * f.pow(0.6)).toFloat()
            val ein = min(1.0, a / 0.4)
            val aus = if (a > RING_DAUER - 2) max(0.0, (RING_DAUER - a) / 2) else 1.0
            return Zustand(ort, radius, (ein * aus).toFloat())
        }

        /** Umriss einer Rauchwolke: rundum Beulen mit kleinen Dellen dazwischen, die sich langsam verformen. */
        fun wolke(form: Form, zeit: Double, mitte: Offset, radius: Float): Path {
            // Die Beulen ragen etwas über den Grundkreis hinaus.
            val r0 = radius
            val k = form.buckel.toDouble()
            val pfad = Path()
            val schritte = 96
            for (i in 0 until schritte) {
                val w = i.toDouble() / schritte * 2 * Math.PI
                val verzogen = w + form.verzug * sin(w + form.p1)
                var r = 1 + form.a2 * sin(2 * w + form.p2 + zeit * 0.5) + form.a3 * sin(3 * w + form.p3 - zeit * 0.4)
                val buckel = abs(sin(k * (verzogen + form.dreh + zeit * 0.12) / 2))
                r *= 0.8 + 0.2 * sqrt(buckel)
                val x = mitte.x + r0 * (r * cos(w) * form.streck).toFloat()
                val y = mitte.y + r0 * (r * sin(w) / form.streck).toFloat()
                if (i == 0) pfad.moveTo(x, y) else pfad.lineTo(x, y)
            }
            pfad.close()
            return pfad
        }
    }
}

/**
 * Tipps auf Wolken – gehört an die Fläche, die Liste und Wolken gemeinsam umfasst. Sie sieht jeden Tipp zuerst:
 * Liegt eine Wolke darunter, bekommt nur die Wolke ihn, sonst geht er ganz normal an die Liste.
 */
fun Modifier.wolkenTippen(rauch: Rauch): Modifier = pointerInput(rauch) {
    awaitEachGesture {
        val unten = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        val p = unten.position / rauch.dichte
        val ring = rauch.getroffen(p, System.currentTimeMillis()) ?: return@awaitEachGesture
        unten.consume()
        val hoch = waitForUpOrCancellation(PointerEventPass.Initial)
        if (hoch != null) {
            hoch.consume()
            rauch.antippen(ring)
        }
    }
}

/**
 * Liegt über der ganzen Suche und zeigt Wolken und Sprüche; Berührungen gehen hindurch.
 * Die Uhr wird nur beim Zeichnen gelesen – bei jedem Bild wird gemalt, aber nichts neu aufgebaut.
 */
@Composable
fun RauchBild(rauch: Rauch, modifier: Modifier = Modifier) {
    val farbe = MaterialTheme.colorScheme.onBackground
    val hinten = MaterialTheme.colorScheme.background
    val dichte = LocalDensity.current.density
    val jetzt = remember { mutableLongStateOf(System.currentTimeMillis()) }
    val flaeche = remember { floatArrayOf(0f, 0f) }
    val leer = rauch.istLeer
    LaunchedEffect(leer) {
        var bild = 0
        while (!rauch.istLeer) {
            withFrameMillis { }
            val t = System.currentTimeMillis()
            jetzt.longValue = t
            // Aufräumen reicht alle paar Bilder; Verblasstes ist ohnehin unsichtbar.
            if (bild++ % 10 == 0) rauch.aufraeumen(t)
        }
    }
    Box(
        modifier
            .fillMaxSize()
            .onGloballyPositioned {
                rauch.flaeche = it.positionInRoot()
                rauch.dichte = dichte
                flaeche[0] = it.size.width / dichte
                flaeche[1] = it.size.height / dichte
            }
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val t = jetzt.longValue
            inDp {
                for (ring in rauch.ringe) {
                    val z = Rauch.zustand(ring, t)
                    if (z.deckkraft <= 0f) continue
                    val alter = (t - ring.geburt) / 1000.0
                    val pfad = Rauch.wolke(ring.form, alter, z.ort, z.radius)
                    drawPath(pfad, farbe.copy(alpha = 0.04f * z.deckkraft))
                    drawPath(pfad, farbe.copy(alpha = 0.55f * z.deckkraft), style = RAND)
                }
                // Zerplatzende Wolken: blähen sich kurz auf und zerfallen in kleine Fetzen, die davonstieben.
                for (p in rauch.platzer) {
                    val f = min(1.0, (t - p.geburt) / 1000.0 / Rauch.PLATZ_DAUER).toFloat()
                    if (f >= 1f) continue
                    val raus = 1 - (1 - f) * (1 - f)
                    drawPath(
                        Rauch.wolke(p.form, 0.0, p.ort, p.radius * (1 + 0.3f * raus)),
                        farbe.copy(alpha = 0.55f * max(0f, 1 - f * 2.5f)), style = PLATZ,
                    )
                    p.fetzen.forEachIndexed { i, w ->
                        val weite = (p.radius + 8) * (0.6f + 0.7f * raus)
                        val g = (5 + i % 3 * 2) * (1 - 0.5f * f) / 2
                        drawCircle(
                            farbe.copy(alpha = 0.5f * (1 - f)), g,
                            Offset(p.ort.x + weite * cos(w).toFloat(), p.ort.y + weite * sin(w).toFloat()),
                            style = FETZEN,
                        )
                    }
                }
            }
        }
        for (s in rauch.sprueche) {
            key(s) { Spruchkarte(s, jetzt, flaeche, farbe, hinten) }
        }
    }
}

private val RAND = strich(1.6f)
private val PLATZ = Stroke(1.6f)
private val FETZEN = Stroke(1.4f)

/** Ein Zen-Spruch, der sanft erscheint und wieder verschwimmt – Ort und Blende werden erst beim Zeichnen berechnet. */
@Composable
private fun Spruchkarte(s: Rauch.Spruch, jetzt: State<Long>, flaeche: FloatArray, farbe: Color, hinten: Color) {
    val breite = 260f
    Box(
        Modifier
            .offset {
                // Im Bild halten, auch wenn die Wolke am Rand war
                val x = min(max(s.ort.x, breite / 2 + 16), flaeche[0] - breite / 2 - 16)
                val y = min(max(s.ort.y, 60f), flaeche[1] - 140)
                IntOffset(((x - breite / 2) * density).toInt(), ((y - 40) * density).toInt())
            }
            .width(breite.dp)
            .graphicsLayer {
                val a = (jetzt.value - s.geburt) / 1000.0
                val ein = min(1.0, a / 0.6).toFloat()
                val aus = (if (a > Rauch.SPRUCH_DAUER - 1.6) max(0.0, (Rauch.SPRUCH_DAUER - a) / 1.6) else 1.0).toFloat()
                val g = 0.9f + 0.1f * ein
                scaleX = g
                scaleY = g
                alpha = ein * aus
                if (Build.VERSION.SDK_INT >= 31) {
                    val r = (1 - aus) * 6.dp.toPx()
                    renderEffect = if (r > 0.5f) BlurEffect(r, r) else null
                    clip = r > 0.5f
                }
            }
            .background(hinten.copy(alpha = 0.85f), RoundedCornerShape(14.dp))
            .padding(vertical = 10.dp, horizontal = 8.dp),
    ) {
        Text(
            s.text,
            fontFamily = FontFamily.Serif,
            fontStyle = FontStyle.Italic,
            fontSize = 20.sp,
            lineHeight = 26.sp,
            textAlign = TextAlign.Center,
            color = farbe,
            modifier = Modifier.width(breite.dp),
        )
    }
}
