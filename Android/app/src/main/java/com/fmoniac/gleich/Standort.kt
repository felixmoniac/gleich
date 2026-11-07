package com.fmoniac.gleich

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

enum class Erlaubnis { unbekannt, erlaubt, verweigert }

/** Wo bin ich? Fragt einmal um Erlaubnis und holt dann bei Bedarf einen frischen Standort. */
class Standort(private val context: Context) {
    private val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    var erlaubnis by mutableStateOf(Erlaubnis.unbekannt)
    var ort by mutableStateOf<Ort?>(null)
        private set

    /** Öffnet die Systemfrage nach dem Standort; setzt die Aktivität. */
    var fragen: (() -> Unit)? = null

    val verweigert: Boolean get() = erlaubnis == Erlaubnis.verweigert
    val erlaubt: Boolean get() = erlaubnis == Erlaubnis.erlaubt

    init {
        pruefen(gefragt = false)
        ort = letzterBekannter() ?: Ablage.letzterOrt
    }

    /** Erlaubnis neu nachsehen – etwa nach der Systemfrage oder der Rückkehr aus den Einstellungen. */
    fun pruefen(gefragt: Boolean) {
        val fein = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
        val grob = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION)
        val schonGefragt = gefragt || Ablage.prefs.getBoolean("ortGefragt", false)
        if (gefragt) Ablage.prefs.edit().putBoolean("ortGefragt", true).apply()
        erlaubnis = when {
            fein == PackageManager.PERMISSION_GRANTED || grob == PackageManager.PERMISSION_GRANTED -> Erlaubnis.erlaubt
            schonGefragt -> Erlaubnis.verweigert
            else -> Erlaubnis.unbekannt
        }
    }

    /** Holt einen frischen Standort; nach spätestens 8 Sekunden gilt der letzte bekannte. */
    suspend fun frisch(): Ort? {
        if (erlaubnis == Erlaubnis.unbekannt) {
            fragen?.invoke()
            // Warten, bis die Frage beantwortet ist.
            repeat(600) {
                if (erlaubnis != Erlaubnis.unbekannt) return@repeat
                delay(100)
            }
        }
        if (!erlaubt) return null
        // Ist der zuletzt bekannte Standort keine zwei Minuten alt, gilt er sofort – das spart oft Sekunden.
        val neu = letzterBekannter(hoechstensAlt = 120_000) ?: withTimeoutOrNull(8000) { aktuell() } ?: letzterBekannter()
        if (neu != null) {
            ort = neu
            Ablage.letzterOrt = neu
        }
        return neu ?: ort
    }

    private fun anbieter(): String? {
        val alle = manager.getProviders(true)
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && LocationManager.FUSED_PROVIDER in alle -> LocationManager.FUSED_PROVIDER
            LocationManager.NETWORK_PROVIDER in alle -> LocationManager.NETWORK_PROVIDER
            LocationManager.GPS_PROVIDER in alle -> LocationManager.GPS_PROVIDER
            else -> alle.firstOrNull { it != LocationManager.PASSIVE_PROVIDER }
        }
    }

    @SuppressLint("MissingPermission")
    private suspend fun aktuell(): Ort? {
        val p = anbieter() ?: return null
        return suspendCancellableCoroutine { weiter ->
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val abbruch = android.os.CancellationSignal()
                    weiter.invokeOnCancellation { abbruch.cancel() }
                    manager.getCurrentLocation(p, abbruch, ContextCompat.getMainExecutor(context)) { l: Location? ->
                        if (weiter.isActive) weiter.resume(l?.let { Ort(it.latitude, it.longitude) })
                    }
                } else {
                    val hoerer = object : LocationListener {
                        override fun onLocationChanged(l: Location) {
                            manager.removeUpdates(this)
                            if (weiter.isActive) weiter.resume(Ort(l.latitude, l.longitude))
                        }
                    }
                    weiter.invokeOnCancellation { manager.removeUpdates(hoerer) }
                    @Suppress("DEPRECATION")
                    manager.requestSingleUpdate(p, hoerer, Looper.getMainLooper())
                }
            } catch (_: Exception) {
                if (weiter.isActive) weiter.resume(null)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun letzterBekannter(hoechstensAlt: Long = Long.MAX_VALUE): Ort? {
        if (!erlaubt) return null
        return try {
            val jetzt = android.os.SystemClock.elapsedRealtimeNanos()
            manager.getProviders(true)
                .mapNotNull { manager.getLastKnownLocation(it) }
                .filter { (jetzt - it.elapsedRealtimeNanos) / 1_000_000 <= hoechstensAlt && it.accuracy <= 150 }
                .maxByOrNull { it.elapsedRealtimeNanos }
                ?.let { Ort(it.latitude, it.longitude) }
        } catch (_: Exception) {
            null
        }
    }
}
