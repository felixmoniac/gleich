package com.fmoniac.gleich

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tram
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import kotlinx.coroutines.delay
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.TextStyle as Wochentag
import java.util.Locale

/** Suche nach einem Ziel. Gemerkte Orte stehen oben, das Eingabefeld unten. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SuchSeite(
    standort: Standort,
    merkliste: Merkliste,
    zweck: Zweck,
    gewaehlt: (Fahrtwunsch) -> Unit,
    schliessen: () -> Unit,
) {
    val blatt = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var text by remember { mutableStateOf("") }
    var treffer by remember { mutableStateOf<List<Ziel>>(emptyList()) }
    var sucht by remember { mutableStateOf(false) }
    /** Gewählte Abfahrtszeit; null heißt jetzt. */
    var ab by remember { mutableStateOf<Long?>(null) }
    var waehltZeit by remember { mutableStateOf(false) }
    val rauch = remember { Rauch() }
    val fokus = remember { FocusRequester() }
    val tastatur = LocalSoftwareKeyboardController.current

    var zuMerken by remember { mutableStateOf<Ziel?>(null) }
    var zuBenennen by remember { mutableStateOf<Gemerkt?>(null) }

    val t = text.trim()
    val suchtNoch = t.isEmpty()
    val gemerkte = when {
        zweck != Zweck.Fahrt -> emptyList()
        t.isEmpty() -> merkliste.orte
        else -> merkliste.orte.filter { it.name.lowercase().contains(t.lowercase()) || it.ziel.name.lowercase().contains(t.lowercase()) }
    }
    val platzhalter = when (zweck) {
        Zweck.Fahrt -> "Wohin?"
        is Zweck.Merken -> when {
            zweck.name == null -> "Welcher Ort?"
            Gemerkt.art(zweck.name) == "arbeit" -> "Wo ist die Arbeit?"
            else -> "Wo ist ${zweck.name}?"
        }
    }

    /** Ein Ziel wurde angetippt. */
    fun waehlen(z: Ziel) {
        rauch.ruht = true
        rauch.leeren()
        tastatur?.hide()
        when (zweck) {
            Zweck.Fahrt -> gewaehlt(Fahrtwunsch(z, ab))
            is Zweck.Merken -> if (zweck.name != null) {
                merkliste.festlegen(z, zweck.name)
                gewaehlt(Fahrtwunsch(z, null))
            } else {
                zuMerken = z
            }
        }
    }

    // Rauchwolken nur, solange nichts getippt ist.
    LaunchedEffect(suchtNoch) {
        rauch.ruht = !suchtNoch
        if (!suchtNoch) rauch.leeren()
    }
    LaunchedEffect(t) {
        if (t.length < 2) {
            treffer = emptyList()
            return@LaunchedEffect
        }
        delay(250)
        sucht = true
        try {
            treffer = Transitous.suchen(t, standort.ort).take(12)
        } catch (_: Exception) {
        } finally {
            sucht = false
        }
    }
    LaunchedEffect(Unit) {
        delay(300)
        try { fokus.requestFocus() } catch (_: Exception) {}
    }

    ModalBottomSheet(
        onDismissRequest = schliessen,
        sheetState = blatt,
        containerColor = MaterialTheme.colorScheme.background,
        modifier = Modifier.statusBarsPadding(),
    ) {
        Box(Modifier.fillMaxSize().imePadding()) {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f).fillMaxWidth().wolkenTippen(rauch)) {
                    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(top = 8.dp, bottom = 12.dp)) {
                        items(gemerkte, key = { "g" + it.id }) { g ->
                            ZielZeile(
                                g.symbol, g.name,
                                zusatz = if (g.name == g.ziel.name) g.ziel.zusatz else g.ziel.name, betont = true,
                                aktion = { waehlen(g.ziel) },
                                menue = listOf(
                                    Triple("Umbenennen", Icons.Filled.Edit) { zuBenennen = g },
                                    Triple("Vergessen", Icons.Filled.Delete) { merkliste.vergessen(g) },
                                ),
                            )
                        }
                        // Adressen ohne eigene Kennung können doppelt vorkommen – die Stelle macht sie eindeutig.
                        itemsIndexed(treffer, key = { i, z -> "t$i:" + z.id }) { _, z ->
                            ZielZeile(
                                if (z.haltID != null) Icons.Filled.Tram else Icons.Filled.Place, z.name, z.zusatz,
                                aktion = { waehlen(z) },
                                menue = listOf(Triple("Merken", Icons.Filled.Star) { zuMerken = z }),
                            )
                        }
                        if (suchtNoch) {
                            item(key = "zug") {
                                // Solange noch nichts gesucht ist: ein kleiner Zug fährt im Kreis.
                                Box(
                                    Modifier.fillMaxWidth().padding(top = if (gemerkte.isEmpty()) 110.dp else 30.dp),
                                    contentAlignment = Alignment.Center,
                                ) { ZugImKreis(rauch) }
                            }
                        }
                        if (sucht && treffer.isEmpty()) {
                            item(key = "lok") {
                                Box(Modifier.fillMaxWidth().padding(top = 30.dp), contentAlignment = Alignment.Center) { Lok(ruckelt = true) }
                            }
                        }
                    }
                    // Rauchwolken und Sprüche über der ganzen Suche – sobald etwas getippt ist, sind sie weg.
                    if (suchtNoch) RauchBild(rauch)
                }
                // Unten: Uhr · Suchfeld · Kreuz
                Row(
                    Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 8.dp, top = 4.dp).navigationBarsPadding(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    if (zweck == Zweck.Fahrt) ZeitKnopf(ab) { waehltZeit = true }
                    Row(
                        Modifier.weight(1f).height(50.dp).glas(RoundedCornerShape(50)).padding(horizontal = 18.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(Icons.Filled.Search, null, tint = zweitrangig)
                        Box(Modifier.weight(1f)) {
                            if (text.isEmpty()) Text(platzhalter, color = zweitrangig, fontSize = 17.sp, fontWeight = FontWeight.Medium)
                            BasicTextField(
                                value = text,
                                onValueChange = { text = it },
                                singleLine = true,
                                textStyle = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onBackground),
                                cursorBrush = SolidColor(MaterialTheme.colorScheme.onBackground),
                                keyboardOptions = KeyboardOptions(
                                    imeAction = ImeAction.Search, autoCorrectEnabled = false,
                                    capitalization = KeyboardCapitalization.Sentences,
                                ),
                                keyboardActions = KeyboardActions(onSearch = {
                                    (gemerkte.firstOrNull()?.ziel ?: treffer.firstOrNull())?.let(::waehlen)
                                }),
                                modifier = Modifier.fillMaxWidth().focusRequester(fokus),
                            )
                        }
                    }
                    Box(Modifier.size(50.dp).glas(CircleShape).clickable(onClick = schliessen), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.Close, "Schließen")
                    }
                }
            }
        }
    }

    if (waehltZeit) ZeitWahl(ab, { waehltZeit = false }) { ab = it; waehltZeit = false }

    zuMerken?.let { z ->
        MerkenDialog(z.name, { zuMerken = null }) { name ->
            merkliste.merken(z, name)
            zuMerken = null
            if (zweck != Zweck.Fahrt) schliessen()
        }
    }
    zuBenennen?.let { g ->
        MerkenDialog(g.name, { zuBenennen = null }, titel = "Umbenennen", knopf = "Sichern") { name ->
            merkliste.umbenennen(g, name)
            zuBenennen = null
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ZielZeile(
    symbol: androidx.compose.ui.graphics.vector.ImageVector,
    name: String,
    zusatz: String?,
    betont: Boolean = false,
    aktion: () -> Unit,
    menue: List<Triple<String, androidx.compose.ui.graphics.vector.ImageVector, () -> Unit>>,
) {
    var offen by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .combinedClickable(onLongClick = { offen = true }, onClick = aktion)
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Icon(symbol, null, tint = if (betont) MaterialTheme.colorScheme.onBackground else zweitrangig, modifier = Modifier.width(28.dp))
            Column {
                Text(name, fontSize = 17.sp, fontWeight = if (betont) FontWeight.SemiBold else FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (!zusatz.isNullOrEmpty()) Text(zusatz, fontSize = 15.sp, color = zweitrangig, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        DropdownMenu(offen, onDismissRequest = { offen = false }) {
            for ((text, bild, tun) in menue) {
                DropdownMenuItem(text = { Text(text) }, leadingIcon = { Icon(bild, null) }, onClick = { offen = false; tun() })
            }
        }
    }
}

/** Abfahrtszeit wählen – oder zurück auf „Jetzt“. Tag als Reihe zum Antippen, darunter die Uhr. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ZeitWahl(ab: Long?, schliessen: () -> Unit, fertig: (Long?) -> Unit) {
    val zone = ZoneId.systemDefault()
    val anfang = ab?.let { java.time.Instant.ofEpochMilli(it).atZone(zone).toLocalDateTime() } ?: LocalDateTime.now()
    val heute = LocalDate.now()
    var tag by remember { mutableIntStateOf(java.time.temporal.ChronoUnit.DAYS.between(heute, anfang.toLocalDate()).toInt().coerceIn(0, 6)) }
    val uhr = rememberTimePickerState(anfang.hour, anfang.minute, is24Hour = true)
    Dialog(onDismissRequest = schliessen) {
        Column(
            Modifier.background(MaterialTheme.colorScheme.background, RoundedCornerShape(28.dp)).padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (i in 0..6) {
                    val d = heute.plusDays(i.toLong())
                    val name = when (i) {
                        0 -> "Heute"
                        1 -> "Morgen"
                        else -> d.dayOfWeek.getDisplayName(Wochentag.SHORT, Locale.GERMANY) + " " + d.dayOfMonth + "."
                    }
                    FilterChip(selected = tag == i, onClick = { tag = i }, label = { Text(name) })
                }
            }
            TimePicker(
                uhr,
                colors = TimePickerDefaults.colors(
                    selectorColor = MaterialTheme.colorScheme.onBackground,
                    timeSelectorSelectedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    clockDialColor = MaterialTheme.colorScheme.surfaceVariant,
                ),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = { fertig(null) }, modifier = Modifier.weight(1f).height(44.dp)) { Text("Jetzt") }
                Button(onClick = {
                    val zeit = heute.plusDays(tag.toLong()).atTime(uhr.hour, uhr.minute).atZone(zone).toInstant().toEpochMilli()
                    fertig(maxOf(zeit, System.currentTimeMillis()))
                }, modifier = Modifier.weight(1f).height(44.dp)) { Text("Fertig", fontWeight = FontWeight.SemiBold) }
            }
        }
    }
}
