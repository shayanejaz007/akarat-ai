# R8 rules for the release build. Flutter's own rules are applied by the
# Flutter Gradle plugin; these cover what the plugins load by reflection.

# Google Maps SDK
-keep class com.google.android.gms.maps.** { *; }
-dontwarn com.google.android.gms.**

# Flutter deferred components reference Play Core classes that are not
# shipped in this app.
-dontwarn com.google.android.play.core.**
