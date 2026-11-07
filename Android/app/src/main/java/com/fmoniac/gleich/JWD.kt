package com.fmoniac.gleich

import androidx.compose.foundation.layout.Spacer
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/** Strichzeichnung: Acker, schiefes Haltestellenschild, Kuh, rollender Steppenläufer. */
@Composable
fun JWDBild(modifier: Modifier = Modifier) {
    val farbe = MaterialTheme.colorScheme.onBackground
    val papier = MaterialTheme.colorScheme.background
    val uhr = rememberUhr()
    val messer = rememberTextMeasurer()
    // Acker, Schild und das „H“ entstehen nur einmal; bei jedem Bild bewegen sich nur Kuh und Steppenläufer.
    Spacer(modifier.requiredSize(320.dp, 230.dp).drawWithCache {
        val breite = size.width / density
        val hoehe = size.height / density
        val s = strich(1.8f)
        val land = landschaft(breite, hoehe)
        val schild = schild()
        val h = messer.measure("H", TextStyle(fontSize = (15f / fontScale).sp, fontWeight = FontWeight.Black, color = farbe))
        val hOrt = Offset(101f * density - h.size.width / 2f, 64f * density - h.size.height / 2f)
        onDrawBehind {
            val t = uhr.value
            inDp {
                drawPath(land, farbe, style = s)
                // Kuh und Schild decken die Ackerfurchen dahinter ab.
                val kuh = kuh(t)
                drawPath(kuh, papier)
                drawPath(kuh, farbe, style = s)
                drawPath(schild, papier)
                drawPath(schild, farbe, style = s)
                drawPath(steppenlaeufer(t, breite), farbe, style = Stroke(1.2f))
            }
            // Das „H“ im Schild – Text wird in Bildpunkten gemessen, daher außerhalb der dp-Zeichnung.
            drawText(h, topLeft = hOrt)
        }
    })
}

private fun landschaft(breite: Float, hoehe: Float): Path {
    val p = Path()
    // Horizont mit sanftem Hügel
    p.moveTo(0f, 128f)
    p.cubicTo(90f, 112f, 200f, 136f, breite, 124f)
    // Ackerfurchen laufen zum Fluchtpunkt
    val fx = 170f
    var unten = -160f
    while (unten <= 480f) {
        p.linie(fx + (unten - fx) * 0.08f, 131f, unten, hoehe)
        unten += 64f
    }
    // Schiefer Mast des Haltestellenschilds
    p.linie(88f, 196f, 99f, 80f)
    // Sonne mit kurzen Strahlen
    val sx = 278f
    val sy = 34f
    p.oval(sx - 11, sy - 11, 22f, 22f)
    for (i in 0 until 8) {
        val w = i * Math.PI / 4
        p.linie(sx + (cos(w) * 16).toFloat(), sy + (sin(w) * 16).toFloat(), sx + (cos(w) * 22).toFloat(), sy + (sin(w) * 22).toFloat())
    }
    // Eine Wolke
    p.moveTo(146f, 48f)
    p.lineTo(206f, 48f)
    p.bogen(196f, 34f, 210f, 36f)
    p.bogen(172f, 26f, 192f, 18f)
    p.bogen(154f, 34f, 158f, 22f)
    p.bogen(146f, 48f, 140f, 38f)
    return p
}

private fun schild(): Path {
    val p = Path()
    // Rundes Schild
    p.oval(86f, 50f, 30f, 30f)
    // Fahrplankasten, leer
    p.rund(80f, 118f, 22f, 26f, 2f)
    p.linie(84f, 125f, 97f, 125f)
    // Grasbüschel am Fuß
    for (x in listOf(78f, 84f, 92f, 98f)) p.linie(x, 198f, x + 2, 189f)
    return p
}

private fun kuh(t: Double): Path {
    val p = Path()
    val kauen = (sin(t * 4) * 1.2).toFloat()
    // Sie steht vorne im Acker, nicht auf dem Horizont.
    val dy = 32f
    // Körper
    p.rund(196f, 100f + dy, 64f, 32f, 14f)
    // Flecken
    p.oval(214f, 106f + dy, 14f, 10f)
    p.oval(238f, 114f + dy, 11f, 9f)
    // Beine
    for (x in listOf(204f, 214f, 242f, 252f)) p.linie(x, 131f + dy, x, 154f + dy)
    // Euter
    p.moveTo(226f, 132f + dy); p.bogen(236f, 132f + dy, 231f, 140f + dy)
    // Schwanz
    val wedel = (sin(t * 2.3) * 5).toFloat()
    p.moveTo(260f, 106f + dy)
    p.bogen(268f + wedel, 136f + dy, 274f, 116f + dy)
    // Kopf, schaut zum Schild
    p.rund(176f, 92f + dy, 24f, 20f, 8f)
    // Maul (kaut)
    p.rund(172f, 104f + kauen * 0.3f + dy, 16f, 11f + kauen, 5f)
    p.oval(175.5f, 108f + dy, 2f, 2f)
    p.oval(181f, 108f + dy, 2f, 2f)
    // Auge
    p.oval(182f, 97f + dy, 3f, 3f)
    // Hörner und Ohr
    p.moveTo(182f, 92f + dy); p.bogen(178f, 82f + dy, 176f, 88f + dy)
    p.moveTo(194f, 92f + dy); p.bogen(198f, 82f + dy, 200f, 88f + dy)
    p.moveTo(200f, 96f + dy); p.lineTo(208f, 92f + dy); p.lineTo(202f, 102f + dy)
    return p
}

private fun steppenlaeufer(t: Double, breite: Float): Path {
    val strecke = breite + 80
    val x = ((t * 34) % strecke).toFloat() - 40
    val r = 13f
    val y = 196 - r - abs(sin(x / 18.0)).toFloat() * 7
    val dreh = x / r.toDouble()
    val p = Path()
    // Ein Knäuel aus versetzten Bögen
    for (i in 0 until 7) {
        val w = dreh + i * 0.9
        val rr = r * (0.55f + 0.45f * (i % 3) / 2f)
        val mx = x + (cos(w) * 2).toFloat()
        val my = y + (sin(w) * 2).toFloat()
        p.arcTo(
            androidx.compose.ui.geometry.Rect(mx - rr, my - rr, mx + rr, my + rr),
            Math.toDegrees(w).toFloat(), Math.toDegrees(3.6).toFloat(), forceMoveTo = true,
        )
    }
    return p
}
