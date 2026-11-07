package com.fmoniac.gleich

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Links von der Startseite: App, Verbund, Netzpläne, Anleitung. */
@Composable
fun Uebersicht(plaene: Planablage, quelleVBB: Boolean, unten: Dp) {
    var offen by remember { mutableStateOf<Netzplan?>(null) }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier
                .widthIn(max = InhaltBreite)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .padding(start = 20.dp, end = 20.dp, bottom = unten + 40.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            Row(Modifier.padding(top = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Image(painterResource(R.drawable.symbol), null, Modifier.size(60.dp).clip(RoundedCornerShape(14.dp)))
                Text("Gleich", fontSize = 34.sp, fontWeight = FontWeight.Bold)
            }
            VerbundWahl(plaene)
            val liste = plaene.plaene
            if (liste.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    for (paar in liste.chunked(2)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            for (p in paar) {
                                val bereit = plaene.istBereit(p)
                                Box(Modifier.weight(1f).clickable(enabled = bereit) { offen = p }) { PlanKachel(plaene, p, bereit) }
                            }
                            if (paar.size == 1) Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
            AnleitungKasten()
            Text(
                "Daten: Transitous" + (if (quelleVBB) " · VBB" else "") + " · Fußwege: OpenStreetMap",
                fontSize = 11.sp, color = zweitrangig.copy(alpha = 0.7f),
            )
        }
    }
    offen?.let { p -> PlanAnsicht(plaene, p) { offen = null } }
}

/** Verbundname; ein Tipp öffnet die Auswahl. Ortspfeil = automatisch, Stecknadel = von Hand gewählt. */
@Composable
private fun VerbundWahl(plaene: Planablage) {
    var auf by remember { mutableStateOf(false) }
    val bereich = rememberCoroutineScope()
    Box {
        Row(
            Modifier.clickable { auf = true },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(if (plaene.wahl == null) Icons.Filled.MyLocation else Icons.Filled.PushPin, null, tint = zweitrangig, modifier = Modifier.size(18.dp))
            Text(plaene.verbund?.name ?: "Fahrpläne für ganz Deutschland", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f, fill = false))
            Icon(Icons.Filled.UnfoldMore, null, tint = zweitrangig.copy(alpha = 0.6f), modifier = Modifier.size(18.dp))
        }
        DropdownMenu(auf, onDismissRequest = { auf = false }) {
            DropdownMenuItem(
                text = { Text("Automatisch" + (plaene.automatisch?.let { " (${it.kuerzel})" } ?: "")) },
                leadingIcon = { Icon(if (plaene.wahl == null) Icons.Filled.Check else Icons.Filled.MyLocation, null) },
                onClick = { auf = false; bereich.launch { plaene.waehlen(null) } },
            )
            HorizontalDivider()
            for (v in Verbund.alle.sortedBy { it.name }) {
                DropdownMenuItem(
                    text = { Text(v.name) },
                    leadingIcon = if (plaene.wahl == v.kuerzel) ({ Icon(Icons.Filled.Check, null) }) else null,
                    onClick = { auf = false; bereich.launch { plaene.waehlen(v.kuerzel) } },
                )
            }
        }
    }
}

@Composable
private fun PlanKachel(plaene: Planablage, plan: Netzplan, bereit: Boolean) {
    var bild by remember(plan.id, bereit) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(plan.id, bereit) {
        if (bereit) bild = withContext(Dispatchers.IO) { PdfBild.seite(plaene.datei(plan), 360, zwischenspeichern = true) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(
            Modifier.fillMaxWidth().height(110.dp).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            val b = bild
            if (b != null) {
                Image(b.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = Alignment.TopStart)
            } else {
                Lok(ruckelt = true, modifier = Modifier.graphicsLayer(scaleX = 0.7f, scaleY = 0.7f))
            }
        }
        Text(plan.titel, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 2)
    }
}

/** Plan bildschirmfüllend, zum Zoomen mit zwei Fingern; Doppeltipp zoomt hinein und wieder heraus. */
@Composable
private fun PlanAnsicht(plaene: Planablage, plan: Netzplan, schliessen: () -> Unit) {
    Dialog(onDismissRequest = schliessen, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            Row(
                Modifier.statusBarsPadding().padding(horizontal = 20.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(plan.titel, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, modifier = Modifier.weight(1f))
                Box(Modifier.size(44.dp).glas(CircleShape).clickable(onClick = schliessen), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Close, "Schließen")
                }
            }
            BoxWithConstraints(Modifier.fillMaxSize().clip(RoundedCornerShape(0.dp))) {
                val breitePx = constraints.maxWidth
                var bild by remember { mutableStateOf<Bitmap?>(null) }
                LaunchedEffect(plan.id) {
                    // Doppelt so fein wie der Bildschirm, damit beim Hineinzoomen die Schrift scharf bleibt –
                    // aber gedeckelt, sonst wird ein großer Plan auf älteren Geräten zum Speicherfresser.
                    bild = withContext(Dispatchers.IO) { PdfBild.seite(plaene.datei(plan), (breitePx * 2).coerceAtMost(2400)) }
                }
                var zoom by remember { mutableFloatStateOf(1f) }
                var versatz by remember { mutableStateOf(Offset.Zero) }
                val b = bild
                if (b == null) {
                    Lok(ruckelt = true, modifier = Modifier.align(Alignment.Center))
                } else {
                    Image(
                        b.asImageBitmap(), plan.titel,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .fillMaxSize()
                            .pointerInput(Unit) {
                                detectTransformGestures { _, verschiebung, faktor, _ ->
                                    zoom = (zoom * faktor).coerceIn(1f, 8f)
                                    val grenzeX = size.width * (zoom - 1) / 2
                                    val grenzeY = size.height * (zoom - 1) / 2
                                    versatz = Offset(
                                        (versatz.x + verschiebung.x).coerceIn(-grenzeX, grenzeX),
                                        (versatz.y + verschiebung.y).coerceIn(-grenzeY, grenzeY),
                                    )
                                }
                            }
                            .pointerInput(Unit) {
                                detectTapGestures(onDoubleTap = {
                                    if (zoom > 1.5f) { zoom = 1f; versatz = Offset.Zero } else zoom = 3f
                                })
                            }
                            .graphicsLayer(scaleX = zoom, scaleY = zoom, translationX = versatz.x, translationY = versatz.y),
                    )
                }
            }
        }
    }
}

/** Kurze Anleitung – auf der Übersicht und beim ersten Start. */
@Composable
fun AnleitungKasten() {
    val punkte = listOf(
        null to "Oben die Haltestellen in deiner Nähe, die nächste zuerst.",
        "Haltestelle antippen:" to "ihre Abfahrten.",
        "Rot:" to "verspätet, das ist die echte Abfahrt.",
        "Blass:" to "zu Fuß wohl nicht mehr zu schaffen.",
        "Abfahrt antippen:" to "alle weiteren Halte.",
        "Haltestellenname oder Männchen antippen:" to "Fußweg dorthin in Google Maps.",
        "Nach rechts wischen:" to "zurück – und auf der Startseite diese Übersicht.",
        "Runterziehen:" to "aktualisieren.",
        "Zuhause, Arbeit, +:" to "Verbindung dorthin; lange drücken wählt einen anderen Ort.",
        "Haltestellenname lange drücken:" to "Ort merken.",
        "Verbundname antippen:" to "andere Netzpläne wählen.",
        "Wohin?" to "Verbindungen von hier; die Uhr daneben wählt die Abfahrtszeit.",
    )
    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(18.dp))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("Anleitung", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        for ((fett, rest) in punkte) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("•", color = zweitrangig, fontSize = 15.sp)
                Text(
                    buildAnnotatedString {
                        fett?.let { withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append("$it ") } }
                        append(rest)
                    },
                    fontSize = 15.sp, lineHeight = 20.sp,
                )
            }
        }
    }
}
