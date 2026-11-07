package com.fmoniac.gleich

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

object Netz {
    /** Transitous möchte wissen, wer anfragt. Kontakt ist die Projektseite, nicht eine Mailadresse. */
    const val KENNUNG = "Gleich-Android/1.0 (+https://github.com/felixmoniac/gleich)"

    private val json = Json { ignoreUnknownKeys = true }

    /** Holt JSON. Parameter mit Wert null werden weggelassen. */
    suspend fun json(basis: String, pfad: String, parameter: Map<String, String?> = emptyMap()): JsonElement =
        withContext(Dispatchers.IO) {
            val anfrage = parameter.mapNotNull { (k, v) ->
                v?.let { URLEncoder.encode(k, "UTF-8") + "=" + URLEncoder.encode(it, "UTF-8") }
            }.joinToString("&")
            val adresse = basis + pfad + if (anfrage.isEmpty()) "" else "?$anfrage"
            json.parseToJsonElement(text(adresse, KENNUNG, accept = "application/json"))
        }

    /** Holt eine Seite als Text. */
    fun text(adresse: String, kennung: String = KENNUNG, accept: String? = null, frist: Int = 12_000): String {
        val v = URL(adresse).openConnection() as HttpURLConnection
        try {
            v.connectTimeout = frist
            v.readTimeout = frist
            v.useCaches = false
            v.setRequestProperty("User-Agent", kennung)
            accept?.let { v.setRequestProperty("Accept", it) }
            if (v.responseCode !in 200..299) throw IOException("Antwort ${v.responseCode}")
            return v.inputStream.bufferedReader().use { it.readText() }
        } finally {
            v.disconnect()
        }
    }
}

// Kleine Helfer zum Lesen von lose getipptem JSON.
fun JsonElement?.obj(): JsonObject? = this as? JsonObject
fun JsonElement?.arr(): List<JsonElement> = (this as? JsonArray) ?: emptyList()
fun JsonObject.text(k: String): String? {
    val p = this[k] as? JsonPrimitive ?: return null
    if (p is JsonNull) return null
    val s = p.content
    return s.ifEmpty { null }
}
fun JsonObject.zahl(k: String): Double? = (this[k] as? JsonPrimitive)?.doubleOrNull
fun JsonObject.objekt(k: String): JsonObject? = this[k] as? JsonObject
fun JsonObject.liste(k: String): List<JsonObject> = (this[k] as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()
fun JsonObject.wahr(k: String): Boolean = (this[k] as? JsonPrimitive)?.booleanOrNull ?: false
fun JsonObject.datum(k: String): Long? = text(k)?.let(Zeit::lesen)

object Zeit {
    private val deutsch = Locale.GERMANY
    private val uhrFormat = DateTimeFormatter.ofPattern("H:mm", deutsch)
    private val tagFormat = DateTimeFormatter.ofPattern("EE d.M. H:mm", deutsch)

    fun lesen(s: String): Long? = try {
        OffsetDateTime.parse(s).toInstant().toEpochMilli()
    } catch (_: Exception) {
        null
    }

    fun schreiben(ms: Long): String = Instant.ofEpochMilli(ms).truncatedTo(ChronoUnit.SECONDS).toString()

    fun uhr(ms: Long): String = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).format(uhrFormat)

    /** „14:30“, „morgen 8:15“ oder „Fr. 8:15“ – für gewählte Abfahrtszeiten. */
    fun wann(ms: Long): String {
        val z = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault())
        val heute = LocalDate.now()
        return when (z.toLocalDate()) {
            heute -> z.format(uhrFormat)
            heute.plusDays(1) -> "morgen " + z.format(uhrFormat)
            else -> z.format(tagFormat)
        }
    }

    /** „jetzt“, „4 Min“ oder ab einer Stunde die Uhrzeit. */
    fun bis(ms: Long, jetzt: Long = System.currentTimeMillis()): String {
        val min = Math.floorDiv(ms - jetzt, 60_000L)
        return when {
            min < 1 -> "jetzt"
            min < 60 -> "$min Min"
            else -> uhr(ms)
        }
    }
}
