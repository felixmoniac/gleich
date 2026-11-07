package com.fmoniac.gleich

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

/**
 * Eine Haltestelle: Name, bei Bedarf Symbolreihe, darunter die Abfahrten.
 * Tipp auf den Namen oder aufs Männchen zeigt den Fußweg; zurück geht es per Wisch nach rechts.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HaltSeite(modell: HaltModell, umgebung: Umgebung, merkliste: Merkliste, zurueck: () -> Unit) {
    val context = LocalContext.current
    var gewaehlt by remember { mutableStateOf<Abfahrt?>(null) }
    var menue by remember { mutableStateOf(false) }
    var merkName by remember { mutableStateOf<String?>(null) }
    val ort = umgebung.ort

    // Die Zeiten zählen alle zehn Sekunden mit.
    var jetzt by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(10_000)
            jetzt = System.currentTimeMillis()
        }
    }
    LaunchedEffect(modell.id) {
        if (modell.abfahrten.isEmpty() || modell.ohneNetz) modell.laden()
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .wischZurueck(zurueck)
            .background(MaterialTheme.colorScheme.background)
    ) {
        Box(Modifier.fillMaxSize().statusBarsPadding().widthIn(max = InhaltBreite).align(Alignment.TopCenter)) {
            LokScroll(laedt = modell.laedt, aktualisieren = { modell.laden(); jetzt = System.currentTimeMillis() }) {
                Column(Modifier.fillMaxWidth().padding(bottom = 30.dp).navigationBarsPadding()) {
                    // Kopf: Name (Tipp = Fußweg, lange drücken = Merken), Männchen, ggf. Wolke
                    Row(
                        Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Box(Modifier.weight(1f, fill = false)) {
                            Text(
                                Namen.kurz(modell.halt.name, ort),
                                fontSize = 32.sp, lineHeight = 36.sp, fontWeight = FontWeight.Bold,
                                modifier = Modifier.combinedClickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                    onLongClick = { menue = true },
                                    onClick = { Fussweg.zeigen(context, modell.halt) },
                                ),
                            )
                            DropdownMenu(menue, onDismissRequest = { menue = false }) {
                                DropdownMenuItem(
                                    text = { Text("Fußweg") },
                                    leadingIcon = { Icon(Icons.AutoMirrored.Filled.DirectionsWalk, null) },
                                    onClick = { menue = false; Fussweg.zeigen(context, modell.halt) },
                                )
                                DropdownMenuItem(
                                    text = { Text("Merken") },
                                    leadingIcon = { Icon(Icons.Filled.Star, null) },
                                    onClick = { menue = false; merkName = Namen.kurz(modell.halt.name) },
                                )
                                HorizontalDivider()
                                DropdownMenuItem(
                                    text = {
                                        Text(
                                            "Daten: Transitous" + if (modell.halt.quelle == Quelle.vbb) " · VBB" else "",
                                            fontSize = 12.sp, color = zweitrangig,
                                        )
                                    },
                                    enabled = false,
                                    onClick = {},
                                )
                            }
                        }
                        Fussknopf(modell.halt, umgebung.gehzeit(modell.halt))
                        if (modell.ohneNetz || umgebung.ohneNetz) {
                            Icon(Icons.Outlined.CloudOff, null, tint = zweitrangig, modifier = Modifier.size(22.dp))
                        }
                        Spacer(Modifier.weight(0.001f))
                    }
                    val mittel = modell.mittel
                    if (mittel.size > 1) {
                        Row(Modifier.padding(start = 20.dp, end = 20.dp, top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            for (m in mittel) {
                                Box(
                                    Modifier
                                        .alpha(if (modell.filter == null || modell.filter == m) 1f else 0.3f)
                                        .clickable { modell.filter = if (modell.filter == m) null else m }
                                ) { MittelSymbol(m) }
                            }
                        }
                    }
                    Spacer(Modifier.height(14.dp))
                    val liste = modell.sichtbar(jetzt) { umgebung.erreichbar(it, modell.halt, jetzt) }
                    if (liste.isEmpty() && !modell.laedt && !umgebung.laedt && !modell.ohneNetz) {
                        Text("Hier fährt so bald nichts.", color = zweitrangig, modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp))
                    }
                    for (a in liste) {
                        AbfahrtZeile(
                            a, ort, jetzt,
                            erreichbar = umgebung.erreichbar(a, modell.halt, jetzt),
                            modifier = Modifier
                                .alpha(if (modell.ohneNetz) 0.35f else 1f)
                                .clickable { gewaehlt = a },
                        )
                    }
                }
            }
        }
    }

    gewaehlt?.let { a -> FahrtSeite(a, ort) { gewaehlt = null } }

    merkName?.let { start ->
        MerkenDialog(start, { merkName = null }) { name ->
            val h = modell.halt
            merkliste.merken(Ziel(h.id, h.name, null, h.breite, h.laenge, if (h.quelle == Quelle.transitous) h.id else null), name)
            merkName = null
        }
    }
}

@Composable
fun AbfahrtZeile(abfahrt: Abfahrt, ort: String?, jetzt: Long, erreichbar: Boolean, modifier: Modifier = Modifier) {
    val aus = if (abfahrt.faelltAus) TextDecoration.LineThrough else null
    Row(
        modifier
            .fillMaxWidth()
            .alpha(if (abfahrt.faelltAus) 0.45f else if (erreichbar) 1f else 0.35f)
            .padding(horizontal = 20.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        LinienSymbol(abfahrt.linie)
        Text(
            Namen.kurz(abfahrt.richtung, ort), fontSize = 17.sp, fontWeight = FontWeight.Medium,
            maxLines = 1, overflow = TextOverflow.Ellipsis, textDecoration = aus, modifier = Modifier.weight(1f),
        )
        abfahrt.gleis?.let { Text("Gl. $it", fontSize = 11.sp, color = zweitrangig) }
        Text(
            Zeit.bis(abfahrt.zeit, jetzt),
            fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textDecoration = aus,
            color = if (abfahrt.verspaetet) Rot else MaterialTheme.colorScheme.onBackground,
            textAlign = androidx.compose.ui.text.style.TextAlign.End,
            modifier = Modifier.widthIn(min = 56.dp),
        )
    }
}

/** Weiterer Weg einer Abfahrt: die nächsten Halte mit Uhrzeit. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FahrtSeite(abfahrt: Abfahrt, ort: String?, schliessen: () -> Unit) {
    val blatt = rememberModalBottomSheetState()
    var halte by remember { mutableStateOf<List<Zwischenhalt>>(emptyList()) }
    var laedt by remember { mutableStateOf(true) }
    LaunchedEffect(abfahrt.id) {
        halte = try { Fahrplan.verlauf(abfahrt) } catch (_: Exception) { emptyList() }
        laedt = false
    }
    ModalBottomSheet(onDismissRequest = schliessen, sheetState = blatt, containerColor = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
            Row(
                Modifier.padding(start = 24.dp, end = 16.dp, top = 8.dp, bottom = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                LinienSymbol(abfahrt.linie)
                Text(Namen.kurz(abfahrt.richtung, ort), fontSize = 20.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, modifier = Modifier.weight(1f))
                Box(Modifier.size(40.dp).glas(CircleShape).clickable(onClick = schliessen), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Close, "Schließen", modifier = Modifier.size(20.dp))
                }
            }
            when {
                laedt && halte.isEmpty() -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                    Lok(ruckelt = true)
                }
                halte.isEmpty() -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.CloudOff, null, tint = zweitrangig, modifier = Modifier.size(32.dp))
                }
                else -> Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
                    halte.forEachIndexed { i, h -> HaltZeile(h, ort, erster = i == 0) }
                }
            }
        }
    }
}

@Composable
fun HaltZeile(halt: Zwischenhalt, ort: String?, erster: Boolean = false, klein: Boolean = false) {
    val groesse = if (klein) 15.sp else 17.sp
    Row(
        Modifier.padding(horizontal = 24.dp, vertical = if (klein) 3.dp else 6.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(
            halt.zeit?.let(Zeit::uhr) ?: "", fontSize = groesse,
            color = if (halt.verspaetet) Rot else if (klein) zweitrangig else MaterialTheme.colorScheme.onBackground,
            textAlign = androidx.compose.ui.text.style.TextAlign.End,
            modifier = Modifier.width(48.dp),
        )
        Text(
            Namen.kurz(halt.name, ort), fontSize = groesse,
            fontWeight = if (erster) FontWeight.SemiBold else FontWeight.Normal,
            color = if (klein) zweitrangig else MaterialTheme.colorScheme.onBackground,
            maxLines = 1, overflow = TextOverflow.Ellipsis,
            textDecoration = if (halt.faelltAus) TextDecoration.LineThrough else null,
        )
    }
}

/** Fragt nach dem Namen, unter dem ein Ort gemerkt wird. */
@Composable
fun MerkenDialog(start: String, abbrechen: () -> Unit, titel: String = "Merken als", knopf: String = "Merken", fertig: (String) -> Unit) {
    var name by remember { mutableStateOf(start) }
    AlertDialog(
        onDismissRequest = abbrechen,
        title = { Text(titel) },
        text = { OutlinedTextField(name, { name = it }, singleLine = true, label = { Text("Name") }) },
        confirmButton = { TextButton(onClick = { fertig(name) }) { Text(knopf) } },
        dismissButton = { TextButton(onClick = abbrechen) { Text("Abbrechen") } },
    )
}
