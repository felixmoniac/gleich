package com.fmoniac.gleich

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Work
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.util.UUID

@Serializable
data class Gemerkt(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val ziel: Ziel,
) {
    val symbol: ImageVector get() = symbol(name)

    companion object {
        fun symbol(name: String): ImageVector = when (art(name)) {
            "zuhause" -> Icons.Filled.Home
            "arbeit" -> Icons.Filled.Work
            "schule" -> Icons.Filled.School
            else -> Icons.Filled.Star
        }

        /** Fasst gleichbedeutende Namen zusammen: „Daheim“ ist auch Zuhause. */
        fun art(name: String): String = when (val n = name.lowercase().trim()) {
            "zuhause", "daheim", "zu hause", "home" -> "zuhause"
            "arbeit", "büro", "buero", "job" -> "arbeit"
            "schule", "kita" -> "schule"
            else -> n
        }
    }
}

class Merkliste {
    var orte by mutableStateOf(Ablage.lesen(ListSerializer(Gemerkt.serializer()), "gemerkt") ?: emptyList())
        private set

    fun merken(ziel: Ziel, als: String) {
        val n = als.trim()
        orte = orte + Gemerkt(name = n.ifEmpty { ziel.name }, ziel = ziel)
        sichern()
    }

    /** Der gemerkte Ort für Zuhause, Arbeit usw., falls es ihn gibt. */
    fun ort(name: String): Gemerkt? = orte.firstOrNull { Gemerkt.art(it.name) == Gemerkt.art(name) }

    /** Wie merken, ersetzt aber einen Ort gleichen Namens (etwa ein neues Zuhause). */
    fun festlegen(ziel: Ziel, als: String) {
        val i = orte.indexOfFirst { Gemerkt.art(it.name) == Gemerkt.art(als) }
        if (i >= 0) {
            orte = orte.toMutableList().also { it[i] = it[i].copy(ziel = ziel) }
            sichern()
        } else {
            merken(ziel, als)
        }
    }

    fun umbenennen(g: Gemerkt, name: String) {
        val n = name.trim()
        if (n.isEmpty()) return
        orte = orte.map { if (it.id == g.id) it.copy(name = n) else it }
        sichern()
    }

    fun vergessen(g: Gemerkt) {
        orte = orte.filter { it.id != g.id }
        sichern()
    }

    private fun sichern() = Ablage.schreiben(ListSerializer(Gemerkt.serializer()), orte, "gemerkt")
}
