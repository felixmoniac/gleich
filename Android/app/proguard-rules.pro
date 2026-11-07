# Gemerkte Orte, Haltestellen und Abfahrten werden über kotlinx.serialization als JSON gespeichert.
# Ohne diese Regeln würde R8 die erzeugten Serialisierer wegwerfen.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

-keepclassmembers class com.fmoniac.gleich.** {
    *** Companion;
}
-keepclasseswithmembers class com.fmoniac.gleich.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.fmoniac.gleich.**$$serializer { *; }
