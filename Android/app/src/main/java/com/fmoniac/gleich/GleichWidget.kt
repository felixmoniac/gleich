package com.fmoniac.gleich

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Was das Widget zeigt. */
private data class Eintrag(val halt: String?, val abfahrten: List<Abfahrt>, val jwd: Boolean = false)

/**
 * Startbildschirm-Widget: die nächsten Abfahrten an der Haltestelle in der Nähe.
 * Es nimmt den Standort, den die App zuletzt kannte – im Hintergrund fragt Android ohne
 * Sondererlaubnis keinen frischen ab. Die App frischt das Widget bei jedem Laden mit auf.
 * Statt „in 4 Min“ stehen Uhrzeiten da: Widgets zählen auf Android nicht minütlich mit.
 */
class GleichWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        Ablage.einrichten(context)
        val e = holen()
        provideContent { Ansicht(e) }
    }

    companion object {
        private val bereich = CoroutineScope(SupervisorJob() + Dispatchers.Default)

        fun auffrischen(context: Context) {
            bereich.launch {
                try {
                    GleichWidget().updateAll(context.applicationContext)
                } catch (_: Exception) {
                }
            }
        }

        private suspend fun holen(): Eintrag {
            val ort = Ablage.letzterOrt ?: return Eintrag(null, emptyList())
            return try {
                val alle = Fahrplan.kandidaten(ort)
                // Echte Fußwege wie in der App; Widgets haben wenig Zeit, deshalb kürzere Frist.
                val wege = Gehwege.zeiten(ort, Gehwege.auswahl(alle, ort), fristMs = 5000)
                val gehzeit = { h: Haltestelle -> wege[h.id] ?: Fahrplan.gehzeit(ort, h) }
                val halt = Fahrplan.auswaehlen(alle, gehzeit).firstOrNull() ?: return Eintrag(null, emptyList())
                if (halt.ort.abstand(ort) > Fahrplan.JWD_METER) return Eintrag(null, emptyList(), jwd = true)
                val gehen = gehzeit(halt) * 1000
                val jetzt = System.currentTimeMillis()
                val ortsname = Namen.ortAus(halt.name)
                // Nur, was man zu Fuß noch schafft.
                val liste = Fahrplan.abfahrten(halt)
                    .filter { !it.faelltAus && it.zeit - jetzt >= gehen }
                    .map { it.copy(richtung = Namen.kurz(it.richtung, ortsname)) }
                    .take(3)
                Eintrag(Namen.kurz(halt.name), liste)
            } catch (_: Exception) {
                Eintrag(null, emptyList())
            }
        }
    }
}

class GleichWidgetEmpfaenger : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = GleichWidget()
}

private val vorne = ColorProvider(day = Color(0xFF111111), night = Color.White)
private val grau = ColorProvider(day = Color(0xFF7A7A80), night = Color(0xFF9A9AA0))
private val hinten = ColorProvider(day = Color.White, night = Color(0xFF1C1C1E))

@Composable
private fun Ansicht(e: Eintrag) {
    Column(
        GlanceModifier
            .fillMaxSize()
            .background(hinten)
            .cornerRadius(22.dp)
            .padding(14.dp)
            .clickable(actionStartActivity<MainActivity>()),
    ) {
        when {
            e.jwd -> Box(GlanceModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("JWD – dit tut weh", style = TextStyle(color = vorne, fontSize = 17.sp, fontWeight = FontWeight.Bold))
            }
            e.halt != null -> {
                Text(e.halt, maxLines = 1, style = TextStyle(color = vorne, fontSize = 14.sp, fontWeight = FontWeight.Bold))
                Spacer(GlanceModifier.height(8.dp))
                for (a in e.abfahrten) {
                    Row(GlanceModifier.fillMaxWidth().padding(bottom = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            GlanceModifier.background(linienFarbe(a.linie)).cornerRadius(4.dp).padding(horizontal = 5.dp, vertical = 1.dp).width(38.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(a.linie.name, maxLines = 1, style = TextStyle(color = ColorProvider(Color.White, Color.White), fontSize = 11.sp, fontWeight = FontWeight.Bold))
                        }
                        Spacer(GlanceModifier.width(6.dp))
                        Text(a.richtung, maxLines = 1, style = TextStyle(color = vorne, fontSize = 12.sp), modifier = GlanceModifier.defaultWeight())
                        Spacer(GlanceModifier.width(4.dp))
                        Text(
                            Zeit.uhr(a.zeit), maxLines = 1,
                            style = TextStyle(
                                color = if (a.verspaetet) ColorProvider(Rot, Rot) else vorne,
                                fontSize = 12.sp, fontWeight = FontWeight.Bold,
                            ),
                        )
                    }
                }
                if (e.abfahrten.isEmpty()) Text("Hier fährt so bald nichts.", style = TextStyle(color = grau, fontSize = 12.sp))
            }
            else -> Box(GlanceModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Gleich öffnen, um den Standort zu finden.", style = TextStyle(color = grau, fontSize = 12.sp))
            }
        }
    }
}
