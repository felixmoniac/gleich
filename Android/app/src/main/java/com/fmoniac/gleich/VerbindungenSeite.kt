package com.fmoniac.gleich

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.max
import kotlin.math.roundToInt

/** Die nächsten Verbindungen von hier zum Ziel – ab jetzt oder ab der gewählten Zeit. */
@Composable
fun VerbindungenSeite(wunsch: Fahrtwunsch, standort: Standort, zurueck: () -> Unit) {
    val ziel = wunsch.ziel
    /** Gewählte Abfahrtszeit; null heißt jetzt. Lässt sich unten ändern. */
    var ab by remember { mutableStateOf(wunsch.ab) }
    var waehltZeit by remember { mutableStateOf(false) }
    var liste by remember { mutableStateOf<List<Verbindung>>(emptyList()) }
    var laedt by remember { mutableStateOf(false) }
    var ohneNetz by remember { mutableStateOf(false) }
    var offen by remember { mutableStateOf<String?>(null) }
    /** Nur der neueste Ladevorgang trägt ein – falls die Zeit schnell hintereinander geändert wird. */
    var lauf by remember { mutableIntStateOf(0) }

    suspend fun laden() {
        lauf += 1
        val meiner = lauf
        laedt = true
        try {
            val ort = standort.frisch() ?: return
            val e = Transitous.verbindungen(ort, ziel, ab)
            if (lauf != meiner) return
            liste = e.filter { it.an > System.currentTimeMillis() }.take(6)
            ohneNetz = false
        } catch (_: Exception) {
            if (lauf == meiner) ohneNetz = true
        } finally {
            if (lauf == meiner) laedt = false
        }
    }

    LaunchedEffect(ab) {
        offen = null
        laden()
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .wischZurueck(zurueck)
            .background(MaterialTheme.colorScheme.background)
    ) {
        Box(Modifier.fillMaxSize().statusBarsPadding().widthIn(max = InhaltBreite).align(Alignment.TopCenter)) {
            LokScroll(laedt = laedt, aktualisieren = { laden() }) {
                Column(Modifier.fillMaxWidth().padding(bottom = 110.dp)) {
                    Row(
                        Modifier.padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(Namen.kurz(ziel.name), fontSize = 32.sp, lineHeight = 36.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f, fill = false))
                        if (ohneNetz) Icon(Icons.Outlined.CloudOff, null, tint = zweitrangig, modifier = Modifier.size(22.dp))
                    }
                    for (v in liste) {
                        VerbindungZeile(v, offen == v.id) { offen = if (offen == v.id) null else v.id }
                    }
                }
            }
        }
        // Unten: zurück, Abfahrtszeit ändern, spätere Verbindungen.
        Row(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(Brush.verticalGradient(0f to Color.Transparent, 0.45f to MaterialTheme.colorScheme.background))
                .navigationBarsPadding()
                .padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 8.dp)
                .widthIn(max = InhaltBreite),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(Modifier.size(50.dp).glas(CircleShape).clickable(onClick = zurueck), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.ChevronLeft, "Zurück")
            }
            ZeitKnopf(ab) { waehltZeit = true }
            Spacer(Modifier.weight(1f))
            Row(
                Modifier
                    .height(50.dp)
                    .alpha(if (liste.isEmpty()) 0.4f else 1f)
                    .glas(RoundedCornerShape(50))
                    .clickable(enabled = liste.isNotEmpty()) {
                        // Ab eine Minute nach der letzten gezeigten Abfahrt weitersuchen
                        liste.lastOrNull()?.let { ab = it.ab + 60_000 }
                    }
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Später", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                Icon(Icons.Filled.ChevronRight, null, modifier = Modifier.size(20.dp))
            }
        }
    }

    if (waehltZeit) ZeitWahl(ab, { waehltZeit = false }) { ab = it; waehltZeit = false }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun VerbindungZeile(v: Verbindung, offen: Boolean, tippen: () -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        FlowRow(
            Modifier.fillMaxWidth().clickable(onClick = tippen).padding(horizontal = 20.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(Zeit.uhr(v.ab), fontSize = 20.sp, fontWeight = FontWeight.SemiBold,
                    color = if (v.ab - v.abGeplant >= 60_000) Rot else MaterialTheme.colorScheme.onBackground)
                Icon(Icons.AutoMirrored.Filled.ArrowForward, null, tint = zweitrangig, modifier = Modifier.size(18.dp))
                Text(Zeit.uhr(v.an), fontSize = 20.sp, fontWeight = FontWeight.SemiBold,
                    color = if (v.an - v.anGeplant >= 60_000) Rot else MaterialTheme.colorScheme.onBackground)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                v.fahrten.forEachIndexed { i, a ->
                    if (i > 0) Text("›", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = zweitrangig)
                    a.linie?.let { LinienSymbol(it, klein = true) }
                }
                if (v.fahrten.isEmpty()) Icon(Icons.AutoMirrored.Filled.DirectionsWalk, null, tint = zweitrangig)
            }
        }
        AnimatedVisibility(offen, enter = fadeIn(), exit = fadeOut()) {
            Schritte(v, Modifier.padding(bottom = 14.dp))
        }
    }
}

/** Aufgeklappte Verbindung: wo einsteigen, welche Linie, wo umsteigen, Fußwege. */
@Composable
private fun Schritte(v: Verbindung, modifier: Modifier) {
    var halteOffen by remember { mutableStateOf(setOf<Int>()) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        for (a in v.abschnitte) {
            if (a.istFussweg) {
                val min = max(1, ((a.an - a.ab) / 60_000.0).roundToInt())
                Row(Modifier.padding(horizontal = 24.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(48.dp), contentAlignment = Alignment.CenterEnd) {
                        Icon(Icons.AutoMirrored.Filled.DirectionsWalk, null, tint = zweitrangig, modifier = Modifier.size(18.dp))
                    }
                    Text("$min Min", fontSize = 15.sp, color = zweitrangig)
                }
            } else {
                Zeile(a.ab, a.abVerspaetet, a.von, a.gleis)
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable { halteOffen = if (a.id in halteOffen) halteOffen - a.id else halteOffen + a.id }
                        .padding(horizontal = 24.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Spacer(Modifier.width(48.dp))
                    a.linie?.let { LinienSymbol(it, klein = true) }
                    Text(Namen.kurz(a.richtung), fontSize = 15.sp, color = zweitrangig, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    if (a.zwischenhalte.isNotEmpty()) {
                        Icon(
                            if (a.id in halteOffen) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown, null,
                            tint = zweitrangig.copy(alpha = 0.6f), modifier = Modifier.size(18.dp),
                        )
                    }
                }
                if (a.id in halteOffen) for (h in a.zwischenhalte) HaltZeile(h, null, klein = true)
                Zeile(a.an, a.anVerspaetet, a.nach, null)
            }
        }
    }
}

@Composable
private fun Zeile(zeit: Long, rot: Boolean, name: String, gleis: String?) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(Zeit.uhr(zeit), fontSize = 17.sp, color = if (rot) Rot else MaterialTheme.colorScheme.onBackground, textAlign = TextAlign.End, modifier = Modifier.width(48.dp))
        Text(Namen.kurz(name), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        gleis?.let { Text("Gl. $it", fontSize = 11.sp, color = zweitrangig) }
    }
}
