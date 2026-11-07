package com.fmoniac.gleich

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.DirectionsBoat
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.Tram
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

// ---------- Farben: Schwarz auf Weiß bzw. Weiß auf Schwarz, keine eigene Akzentfarbe ----------

val Rot = Color(0xFFE5332A)

@Composable
fun GleichThema(inhalt: @Composable () -> Unit) {
    val dunkel = isSystemInDarkTheme()
    val farben = if (dunkel) darkColorScheme(
        primary = Color.White, onPrimary = Color.Black,
        background = Color.Black, onBackground = Color.White,
        surface = Color.Black, onSurface = Color.White,
        surfaceVariant = Color(0xFF1C1C1E), onSurfaceVariant = Color(0xFF9A9AA0),
        surfaceContainerHigh = Color(0xFF1C1C1E), surfaceContainerLow = Color(0xFF111113),
        surfaceContainerHighest = Color(0xFF2C2C2E), surfaceContainer = Color(0xFF1C1C1E),
        primaryContainer = Color(0xFF2C2C2E), onPrimaryContainer = Color.White,
        secondary = Color.White, onSecondary = Color.Black,
        secondaryContainer = Color(0xFF3A3A3C), onSecondaryContainer = Color.White,
        tertiary = Color.White, tertiaryContainer = Color(0xFF3A3A3C), onTertiaryContainer = Color.White,
        outline = Color(0xFF3A3A3C),
    ) else lightColorScheme(
        primary = Color.Black, onPrimary = Color.White,
        background = Color.White, onBackground = Color(0xFF111111),
        surface = Color.White, onSurface = Color(0xFF111111),
        surfaceVariant = Color(0xFFF2F2F5), onSurfaceVariant = Color(0xFF7A7A80),
        surfaceContainerHigh = Color(0xFFF2F2F5), surfaceContainerLow = Color(0xFFF7F7F9),
        surfaceContainerHighest = Color(0xFFE9E9EE), surfaceContainer = Color(0xFFF2F2F5),
        primaryContainer = Color(0xFFE9E9EE), onPrimaryContainer = Color(0xFF111111),
        secondary = Color(0xFF111111), onSecondary = Color.White,
        secondaryContainer = Color(0xFFE2E2E7), onSecondaryContainer = Color(0xFF111111),
        tertiary = Color(0xFF111111), tertiaryContainer = Color(0xFFE2E2E7), onTertiaryContainer = Color(0xFF111111),
        outline = Color(0xFFDADADF),
    )
    MaterialTheme(colorScheme = farben) {
        CompositionLocalProvider(LocalContentColor provides farben.onBackground, content = inhalt)
    }
}

/** Grau für Nebensächliches. */
val zweitrangig: Color @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant

/** Schwebende Fläche für Knöpfe – das, was auf dem iPhone Glas ist. */
@Composable
fun Modifier.glas(form: Shape = CircleShape): Modifier {
    val c = MaterialTheme.colorScheme
    val dunkel = isSystemInDarkTheme()
    return this
        .shadow(if (dunkel) 0.dp else 6.dp, form, ambientColor = Color.Black.copy(alpha = 0.25f), spotColor = Color.Black.copy(alpha = 0.18f))
        .background(if (dunkel) Color(0xFF242427) else Color.White, form)
        .border(0.5.dp, c.outline.copy(alpha = 0.6f), form)
}

/** Größte Breite für Inhalte – auf Tablets bleibt alles mittig und lesbar. */
val InhaltBreite = 600.dp

// ---------- Liniensymbol ----------

/** Liniensymbol in den vertrauten Farben: S-Bahn rund, U-Bahn eckig, Tram rot, Bus lila. */
@Composable
fun LinienSymbol(linie: Linie, klein: Boolean = false) {
    val form = when (linie.mittel) {
        Verkehrsmittel.sbahn -> RoundedCornerShape(50)
        Verkehrsmittel.ubahn -> RoundedCornerShape(3.dp)
        else -> RoundedCornerShape(if (klein) 4.dp else 6.dp)
    }
    Box(
        Modifier
            .defaultMinSize(minWidth = if (klein) 30.dp else 54.dp, minHeight = if (klein) 18.dp else 24.dp)
            .background(linienFarbe(linie), form)
            .padding(horizontal = if (klein) 5.dp else 7.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            linie.name,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = if (klein) 12.sp else 15.sp,
            maxLines = 1,
            overflow = TextOverflow.Clip,
        )
    }
}

fun linienFarbe(l: Linie): Color = when (l.mittel) {
    Verkehrsmittel.sbahn -> hexFarbe(l.farbe, 0x008D4F)
    Verkehrsmittel.ubahn -> hexFarbe(l.farbe, 0x115D91)
    Verkehrsmittel.tram -> Color(0xFFC8102E)
    Verkehrsmittel.bus -> Color(0xFF8E2C79)
    Verkehrsmittel.regio -> Color(0xFFE2001A)
    Verkehrsmittel.fern -> Color(0xFF3D4147)
    Verkehrsmittel.faehre -> Color(0xFF0098D8)
    Verkehrsmittel.sonst -> Color(0xFF6E6E73)
}

/** Farbe aus Text wie „816da6“; zu helle oder fehlende Farben werden ersetzt. */
private fun hexFarbe(text: String?, sonst: Int): Color {
    val wert = text?.takeIf { it.length == 6 }?.toIntOrNull(16) ?: return Color(0xFF000000.toInt() or sonst)
    val r = (wert shr 16) and 0xFF
    val g = (wert shr 8) and 0xFF
    val b = wert and 0xFF
    val hell = (0.299 * r + 0.587 * g + 0.114 * b) / 255
    val unbunt = maxOf(r, g, b) - minOf(r, g, b) < 20
    return Color(0xFF000000.toInt() or if (hell > 0.8 || unbunt) sonst else wert)
}

/** Kleines Symbol für ein Verkehrsmittel (Filterreihe oben). */
@Composable
fun MittelSymbol(mittel: Verkehrsmittel) {
    val farbe = linienFarbe(Linie("", mittel))
    @Composable
    fun buchstabe(s: String, form: Shape) = Box(
        Modifier.defaultMinSize(minWidth = 30.dp, minHeight = 26.dp).background(farbe, form).padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center,
    ) { Text(s, color = Color.White, fontWeight = FontWeight.Black, fontSize = 14.sp) }

    @Composable
    fun bild(symbol: androidx.compose.ui.graphics.vector.ImageVector) = Box(
        Modifier.size(30.dp, 26.dp).background(farbe, RoundedCornerShape(6.dp)),
        contentAlignment = Alignment.Center,
    ) { Icon(symbol, null, tint = Color.White, modifier = Modifier.size(17.dp)) }

    when (mittel) {
        Verkehrsmittel.sbahn -> buchstabe("S", RoundedCornerShape(50))
        Verkehrsmittel.ubahn -> buchstabe("U", RoundedCornerShape(3.dp))
        Verkehrsmittel.fern -> buchstabe("ICE", RoundedCornerShape(5.dp))
        Verkehrsmittel.regio -> buchstabe("RE", RoundedCornerShape(5.dp))
        Verkehrsmittel.tram -> bild(Icons.Filled.Tram)
        Verkehrsmittel.bus -> bild(Icons.Filled.DirectionsBus)
        Verkehrsmittel.faehre -> bild(Icons.Filled.DirectionsBoat)
        Verkehrsmittel.sonst -> bild(Icons.Filled.Apps)
    }
}

// ---------- Fußweg ----------

/** Das Männchen mit der Gehzeit – ein Tipp zeigt den Fußweg in Google Maps. */
@Composable
fun Fussknopf(halt: Haltestelle, sekunden: Double) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val fuss = (sekunden / 60).roundToInt()
    Row(
        Modifier
            .clickable { Fussweg.zeigen(context, halt) }
            .padding(vertical = 6.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Icon(Icons.AutoMirrored.Filled.DirectionsWalk, "Fußweg", tint = zweitrangig, modifier = Modifier.size(19.dp))
        if (fuss > 1) Text("$fuss Min", color = zweitrangig, fontSize = 16.sp, fontWeight = FontWeight.Medium)
    }
}

object Fussweg {
    /** Öffnet Google Maps mit dem Fußweg zur Haltestelle – ohne Google Maps im Browser. */
    fun zeigen(context: Context, h: Haltestelle) {
        val uri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=${h.breite},${h.laenge}&travelmode=walking")
        val mitApp = Intent(Intent.ACTION_VIEW, uri).setPackage("com.google.android.apps.maps")
        try {
            context.startActivity(mitApp)
        } catch (_: ActivityNotFoundException) {
            try {
                context.startActivity(Intent(Intent.ACTION_VIEW, uri))
            } catch (_: ActivityNotFoundException) {
            }
        }
    }
}

/** Abfahrtszeit: zeigt „Jetzt“ oder die gewählte Zeit, ein Tipp lässt sie ändern. */
@Composable
fun ZeitKnopf(ab: Long?, aktion: () -> Unit) {
    Row(
        Modifier
            .height(50.dp)
            .glas(RoundedCornerShape(50))
            .clickable(onClick = aktion)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(Icons.Filled.AccessTime, null, modifier = Modifier.size(18.dp))
        Text(ab?.let(Zeit::wann) ?: "Jetzt", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/**
 * Zurück per Wisch nach rechts – von überall auf der Seite, nicht nur vom Rand.
 * Die Seite folgt dem Finger; weit genug gezogen, geht es zurück.
 */
@Composable
fun Modifier.wischZurueck(zurueck: () -> Unit): Modifier {
    val versatz = remember { Animatable(0f) }
    val bereich = rememberCoroutineScope()
    val schwelle = with(LocalDensity.current) { 110.dp.toPx() }
    return this
        .offset { IntOffset(versatz.value.roundToInt(), 0) }
        .pointerInput(Unit) {
            detectHorizontalDragGestures(
                onDragEnd = {
                    bereich.launch {
                        if (versatz.value > schwelle) {
                            versatz.animateTo(size.width.toFloat(), spring(stiffness = 900f))
                            zurueck()
                        } else {
                            versatz.animateTo(0f, spring())
                        }
                    }
                },
                onDragCancel = { bereich.launch { versatz.animateTo(0f) } },
            ) { aenderung, dx ->
                aenderung.consume()
                bereich.launch { versatz.snapTo((versatz.value + dx).coerceAtLeast(0f)) }
            }
        }
}

/** Kleine Lücke mit fester Breite. */
@Composable
fun Abstand(b: Int) = Box(Modifier.width(b.dp))
