package com.fmoniac.gleich

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocationOff
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.launch

/** Wohin die Startseite weiterführt. */
sealed interface Schritt {
    /** Abfahrten einer Haltestelle (nach ihrer Kennung). */
    data class Halt(val id: String) : Schritt
    data class Fahrt(val wunsch: Fahrtwunsch) : Schritt
}

/** Wofür gesucht wird: eine Fahrt – oder ein Ort, der gemerkt werden soll (Zuhause, Arbeit oder ganz neu). */
sealed interface Zweck {
    data object Fahrt : Zweck
    data class Merken(val name: String?) : Zweck
}

class MainActivity : ComponentActivity() {
    private lateinit var umgebung: Umgebung

    private val ortsfrage = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        umgebung.standort.pruefen(gefragt = true)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Ablage.einrichten(this)
        enableEdgeToEdge()
        umgebung = Umgebung(this, kotlinx.coroutines.MainScope())
        umgebung.standort.fragen = {
            ortsfrage.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
        }
        val merkliste = Merkliste()
        setContent {
            GleichThema {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    Gleich(umgebung, merkliste)
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Vielleicht kommt man gerade aus den Einstellungen zurück.
        umgebung.standort.pruefen(gefragt = false)
    }
}

@Composable
fun Gleich(umgebung: Umgebung, merkliste: Merkliste) {
    val pfad = remember { mutableStateListOf<Schritt>() }
    var suche by remember { mutableStateOf<Zweck?>(null) }
    var anleitungGesehen by remember { mutableStateOf(Ablage.prefs.getBoolean("anleitungGesehen", false)) }
    var spielt by remember { mutableStateOf(false) }
    val bereich = rememberCoroutineScope()

    // Beim Öffnen und Zurückkehren alles neu; beim Schließen die alten Haltestellen verbergen.
    val lebenslauf = LocalLifecycleOwner.current
    androidx.compose.runtime.DisposableEffect(lebenslauf) {
        val beobachter = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_START -> bereich.launch { umgebung.allesNeu() }
                Lifecycle.Event.ON_STOP -> umgebung.zurueckgelassen()
                else -> Unit
            }
        }
        lebenslauf.lifecycle.addObserver(beobachter)
        onDispose { lebenslauf.lifecycle.removeObserver(beobachter) }
    }
    // Ist eine geöffnete Haltestelle nicht mehr in der Nähe, geht es zurück zur Startseite.
    LaunchedEffect(Unit) {
        snapshotFlow { umgebung.seiten.map { it.id } }.collect { ids ->
            pfad.removeAll { it is Schritt.Halt && it.id !in ids }
        }
    }

    BackHandler(enabled = pfad.isNotEmpty()) { pfad.removeAt(pfad.lastIndex) }

    if (umgebung.standort.verweigert) {
        OrtungFehlt(umgebung.standort)
        return
    }

    AnimatedContent(
        targetState = pfad.lastOrNull(),
        transitionSpec = {
            val vor = targetState != null && (initialState == null || pfad.size > 1)
            if (vor) slideInHorizontally(tween(260)) { it } togetherWith slideOutHorizontally(tween(260)) { -it / 4 }
            else slideInHorizontally(tween(260)) { -it / 4 } togetherWith slideOutHorizontally(tween(260)) { it }
        },
        label = "seite",
    ) { schritt ->
        when (schritt) {
            null -> Startseite(
                umgebung, merkliste,
                oeffnen = { pfad.add(it) },
                suchen = { suche = it },
                spielen = { spielt = true },
            )
            is Schritt.Halt -> umgebung.modell(schritt.id)?.let { m ->
                HaltSeite(m, umgebung, merkliste) { pfad.removeLastOrNull() }
            }
            is Schritt.Fahrt -> VerbindungenSeite(schritt.wunsch, umgebung.standort) { pfad.removeLastOrNull() }
        }
    }

    suche?.let { zweck ->
        SuchSeite(
            standort = umgebung.standort,
            merkliste = merkliste,
            zweck = zweck,
            gewaehlt = { wunsch ->
                suche = null
                pfad.clear()
                pfad.add(Schritt.Fahrt(wunsch))
            },
            schliessen = { suche = null },
        )
    }

    if (spielt) WollalarmSpiel { spielt = false }

    if (!anleitungGesehen) {
        AnleitungHinweis {
            anleitungGesehen = true
            Ablage.prefs.edit().putBoolean("anleitungGesehen", true).apply()
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Startseite(
    umgebung: Umgebung,
    merkliste: Merkliste,
    oeffnen: (Schritt) -> Unit,
    suchen: (Zweck) -> Unit,
    spielen: () -> Unit,
) {
    // Seite 0 ist unsichtbar: Wer zweimal binnen einer Sekunde dorthin wischt, startet das versteckte Spiel.
    val seiten = rememberPagerState(initialPage = 2) { 3 }
    var letzterWisch by remember { mutableLongStateOf(0L) }
    LaunchedEffect(seiten) {
        // Jedes Loslassen des Fingers auf der unsichtbaren Seite zählt als Wisch.
        seiten.interactionSource.interactions.collect { i ->
            if (i !is androidx.compose.foundation.interaction.DragInteraction.Stop || seiten.currentPage != 0) return@collect
            val jetzt = System.currentTimeMillis()
            if (jetzt - letzterWisch < 1500) {
                letzterWisch = 0
                spielen()
            } else {
                letzterWisch = jetzt
            }
        }
    }
    LaunchedEffect(seiten) {
        // Liegt die unsichtbare Seite still, federt sie zurück – auch wenn ein Wisch das Zurückfedern unterbrochen hat.
        snapshotFlow { seiten.isScrollInProgress to seiten.currentPage }.collect { (bewegt, s) ->
            if (!bewegt && s == 0) launch { seiten.animateScrollToPage(1) }
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val bildschirm = maxHeight
        var leiste by remember { mutableStateOf(0.dp) }
        val dichte = LocalDensity.current
        HorizontalPager(seiten, Modifier.fillMaxSize(), beyondViewportPageCount = 1) { s ->
            when (s) {
                0 -> Box(Modifier.fillMaxSize())
                1 -> Uebersicht(umgebung.plaene, umgebung.seiten.firstOrNull()?.halt?.quelle == Quelle.vbb, unten = leiste)
                else -> Nah(umgebung, merkliste, bildschirm, leiste, oeffnen, suchen)
            }
        }
        // Unten fest: Punkte und Suchfeld, die Seiten laufen sanft darunter aus.
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(Brush.verticalGradient(0f to Color.Transparent, 0.45f to MaterialTheme.colorScheme.background))
                .navigationBarsPadding()
                .padding(start = 20.dp, end = 20.dp, top = 22.dp, bottom = 8.dp)
                .onSizeChanged { leiste = with(dichte) { it.height.toDp() } },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Punkte(seiten.currentPage)
            Box(Modifier.widthIn(max = InhaltBreite)) { Suchknopf { suchen(Zweck.Fahrt) } }
        }
    }
}

@Composable
private fun Punkte(seite: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
        // Die Übersicht bekommt ein Zeichen statt eines Punkts.
        Icon(
            Icons.Filled.Info, null, modifier = Modifier.size(10.dp),
            tint = if (seite <= 1) MaterialTheme.colorScheme.onBackground else zweitrangig.copy(alpha = 0.5f),
        )
        Box(
            Modifier.size(7.dp).background(
                if (seite == 2) MaterialTheme.colorScheme.onBackground else zweitrangig.copy(alpha = 0.5f), CircleShape,
            )
        )
    }
}

/** Die Startseite: oben die Haltestellen in der Nähe, ab der Bildschirmmitte die eigenen Orte. */
@Composable
private fun Nah(
    umgebung: Umgebung,
    merkliste: Merkliste,
    bildschirm: androidx.compose.ui.unit.Dp,
    leiste: androidx.compose.ui.unit.Dp,
    oeffnen: (Schritt) -> Unit,
    suchen: (Zweck) -> Unit,
) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.fillMaxWidth().height(bildschirm / 2)) {
            Column(Modifier.fillMaxSize().statusBarsPadding()) {
                Box(Modifier.fillMaxSize().widthIn(max = InhaltBreite).align(Alignment.CenterHorizontally)) {
                    Haltestellenliste(umgebung) { oeffnen(Schritt.Halt(it)) }
                }
            }
        }
        Ortsraster(
            merkliste,
            Modifier.fillMaxWidth().height(bildschirm / 2).widthIn(max = InhaltBreite),
            unten = leiste,
            fahren = { oeffnen(Schritt.Fahrt(Fahrtwunsch(it, null))) },
            festlegen = { suchen(Zweck.Merken(it)) },
        )
    }
}

/** Nur die Namen der nächsten Haltestellen. Ein Tipp öffnet die Abfahrten, das Männchen den Fußweg. */
@Composable
private fun Haltestellenliste(umgebung: Umgebung, oeffnen: (String) -> Unit) {
    // Die Haltestellen stehen über der Mittellinie: die nächste zuoberst, die letzte direkt über der Linie.
    LokScroll(
        laedt = umgebung.laedt || umgebung.standort.erlaubnis == Erlaubnis.unbekannt,
        unten = true,
        aktualisieren = { umgebung.allesNeu() },
    ) {
        Column(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 14.dp)) {
            if (umgebung.jwd && !umgebung.veraltet) {
                Column(Modifier.fillMaxWidth().padding(bottom = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.height(165.dp), contentAlignment = Alignment.Center) {
                        JWDBild(Modifier.scale(0.7f))
                    }
                    Text("JWD – dit tut weh", fontSize = 24.sp, fontWeight = FontWeight.Black)
                }
            }
            for (m in umgebung.sichtbar) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable { oeffnen(m.id) }
                        .padding(horizontal = 20.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        Namen.kurz(m.halt.name, umgebung.ort),
                        fontSize = 28.sp, lineHeight = 32.sp, fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    if (m.ohneNetz || umgebung.ohneNetz) {
                        Icon(Icons.Outlined.CloudOff, null, tint = zweitrangig, modifier = Modifier.size(20.dp))
                    }
                    Spacer(Modifier.weight(0.001f))
                    Fussknopf(m.halt, umgebung.gehzeit(m.halt))
                }
            }
            if (umgebung.sichtbar.isEmpty() && umgebung.ohneNetz && !umgebung.laedt) {
                Icon(
                    Icons.Outlined.CloudOff, null, tint = zweitrangig,
                    modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 60.dp).size(34.dp),
                )
            }
        }
    }
}

/**
 * Unter einer kurzen Linie: Zuhause, Arbeit, weitere gemerkte Orte und „+“ für einen neuen –
 * nebeneinander und untereinander wie die Symbole auf dem Startbildschirm.
 * Ein Tipp sucht gleich die Verbindung dorthin; ist der Ort noch nicht festgelegt, wird er erst gesucht.
 */
@Composable
private fun Ortsraster(
    merkliste: Merkliste,
    modifier: Modifier,
    unten: androidx.compose.ui.unit.Dp,
    fahren: (Ziel) -> Unit,
    festlegen: (String?) -> Unit,
) {
    val weitere = merkliste.orte.filter { Gemerkt.art(it.name) !in listOf("zuhause", "arbeit") }
    BoxWithConstraints(modifier) {
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.fillMaxWidth(0.6f).height(1.dp).background(MaterialTheme.colorScheme.onBackground))
            LazyVerticalGrid(
                columns = GridCells.Fixed(4),
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 20.dp, end = 20.dp, top = 24.dp, bottom = unten + 12.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(18.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                for (name in listOf("Zuhause", "Arbeit")) {
                    item(key = name) {
                        val g = merkliste.ort(name)
                        if (g != null) {
                            Kachel(name, g.symbol, da = true, aktion = { fahren(g.ziel) }, menue = listOf(
                                "Anderen Ort wählen" to { festlegen(name) },
                                "Vergessen" to { merkliste.vergessen(g) },
                            ))
                        } else {
                            Kachel(name, Gemerkt.symbol(name), da = false, aktion = { festlegen(name) })
                        }
                    }
                }
                items(weitere, key = { it.id }) { g ->
                    Kachel(g.name, g.symbol, da = true, aktion = { fahren(g.ziel) }, menue = listOf(
                        "Anderen Ort wählen" to { festlegen(g.name) },
                        "Vergessen" to { merkliste.vergessen(g) },
                    ))
                }
                item(key = "+") { Kachel("Neu", Icons.Filled.Add, da = false, aktion = { festlegen(null) }) }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Kachel(
    name: String,
    symbol: androidx.compose.ui.graphics.vector.ImageVector,
    da: Boolean,
    aktion: () -> Unit,
    menue: List<Pair<String, () -> Unit>> = emptyList(),
) {
    var offen by remember { mutableStateOf(false) }
    val farbe = if (da) MaterialTheme.colorScheme.onBackground else zweitrangig
    Box {
        Column(
            Modifier
                .fillMaxWidth()
                .combinedClickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onLongClick = { if (menue.isNotEmpty()) offen = true },
                    onClick = aktion,
                ),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(Modifier.size(62.dp).glas(RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) {
                Icon(symbol, name, tint = farbe, modifier = Modifier.size(28.dp))
            }
            Text(name, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = farbe, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        DropdownMenu(offen, onDismissRequest = { offen = false }) {
            for ((text, tun) in menue) {
                DropdownMenuItem(
                    text = { Text(text) },
                    leadingIcon = { Icon(if (text == "Vergessen") Icons.Filled.Delete else Icons.Filled.Place, null) },
                    onClick = { offen = false; tun() },
                )
            }
        }
    }
}

/** Das Suchfeld unten. Ein Tipp öffnet die Suche. */
@Composable
private fun Suchknopf(aktion: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(50.dp)
            .glas(RoundedCornerShape(50))
            .clickable(onClick = aktion)
            .padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.Search, null, tint = zweitrangig)
        Text("Wohin?", color = zweitrangig, fontSize = 17.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun OrtungFehlt(standort: Standort) {
    val context = LocalContext.current
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Filled.LocationOff, null, tint = zweitrangig, modifier = Modifier.size(48.dp))
        Text(
            "Gleich braucht deinen Standort, um zu zeigen, was in deiner Nähe abfährt.",
            fontSize = 20.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center,
        )
        Button(
            onClick = {
                val aktivitaet = context as? ComponentActivity
                val nochmal = aktivitaet?.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION) == true
                if (nochmal) {
                    standort.fragen?.invoke()
                } else {
                    context.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                    )
                }
            },
            colors = ButtonDefaults.buttonColors(),
        ) { Text("Einstellungen öffnen") }
    }
}

/** Beim ersten Start: die Anleitung als Kasten, weg mit „OK“. */
@Composable
fun AnleitungHinweis(fertig: () -> Unit) {
    Dialog(onDismissRequest = fertig) {
        Column(
            Modifier
                .background(MaterialTheme.colorScheme.background, RoundedCornerShape(28.dp))
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            AnleitungKasten()
            Button(onClick = fertig, modifier = Modifier.fillMaxWidth().height(50.dp)) {
                Text("OK", fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            }
        }
    }
}
