package com.fmoniac.gleich

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json

/** Kleiner gemeinsamer Speicher von App und Widget. */
object Ablage {
    private lateinit var speicher: SharedPreferences
    val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun einrichten(context: Context) {
        if (!::speicher.isInitialized) {
            speicher = context.applicationContext.getSharedPreferences("gleich", Context.MODE_PRIVATE)
        }
    }

    val prefs: SharedPreferences get() = speicher

    var letzterOrt: Ort?
        get() {
            if (!speicher.contains("ort.b")) return null
            return Ort(
                java.lang.Double.longBitsToDouble(speicher.getLong("ort.b", 0)),
                java.lang.Double.longBitsToDouble(speicher.getLong("ort.l", 0)),
            )
        }
        set(o) {
            if (o == null) return
            speicher.edit()
                .putLong("ort.b", java.lang.Double.doubleToRawLongBits(o.breite))
                .putLong("ort.l", java.lang.Double.doubleToRawLongBits(o.laenge))
                .apply()
        }

    fun <T> lesen(serializer: KSerializer<T>, schluessel: String): T? {
        val s = speicher.getString(schluessel, null) ?: return null
        return try { json.decodeFromString(serializer, s) } catch (_: Exception) { null }
    }

    fun <T> schreiben(serializer: KSerializer<T>, wert: T, schluessel: String) {
        speicher.edit().putString(schluessel, json.encodeToString(serializer, wert)).apply()
    }
}
