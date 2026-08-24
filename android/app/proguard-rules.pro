# Flutter / Dart
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }

# Supabase / GoTrue / Postgrest
-keep class io.supabase.** { *; }
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.supabase.**

# OneSignal
-keep class com.onesignal.** { *; }
-dontwarn com.onesignal.**

# Kotlin / reflection
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses

# Keep native methods
-keepclassmembers class * {
    native <methods>;
}
