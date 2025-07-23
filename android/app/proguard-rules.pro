# ---------------------------------------
# Firebase - General Configuration
# ---------------------------------------

# Keep all Firebase components
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Required for Firebase SDK's reflection
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.google.firebase.components.ComponentRegistrar <methods>;
}

# Allow Firebase's internal components to be referenced
-keepnames class com.google.firebase.** { *; }
-keepnames interface com.google.firebase.** { *; }

# ---------------------------------------
# Firebase Core
# ---------------------------------------
-keep class com.google.firebase.components.ComponentRegistrar { *; }

# ---------------------------------------
# Firebase Analytics
# ---------------------------------------
-keep class com.google.firebase.analytics.** { *; }

# ---------------------------------------
# Firebase Messaging (FCM)
# ---------------------------------------
-keep class com.google.firebase.messaging.** { *; }

# ---------------------------------------
# Firebase Auth
# ---------------------------------------
-keep class com.google.firebase.auth.** { *; }
-dontwarn com.google.firebase.auth.**

# ---------------------------------------
# Firebase Firestore
# ---------------------------------------
-keep class com.google.firebase.firestore.** { *; }
-dontwarn com.google.firebase.firestore.**

# ---------------------------------------
# Firebase Remote Config
# ---------------------------------------
-keep class com.google.firebase.remoteconfig.** { *; }

# ---------------------------------------
# Firebase Crashlytics
# ---------------------------------------
-keep class com.google.firebase.crashlytics.** { *; }
-dontwarn com.google.firebase.crashlytics.**

# Keep Crashlytics internal annotations
-keepattributes SourceFile,LineNumberTable

# ---------------------------------------
# Firebase Installations
# ---------------------------------------
-keep class com.google.firebase.installations.** { *; }

# ---------------------------------------
# Firebase Performance Monitoring (optional)
# ---------------------------------------
-keep class com.google.firebase.perf.** { *; }

# ---------------------------------------
# Firebase ML Model Downloader (optional)
# ---------------------------------------
-keep class com.google.firebase.ml.** { *; }

# ---------------------------------------
# JSON and GSON support (used with Firebase in some cases)
# ---------------------------------------
-keep class com.google.gson.** { *; }
-keep class sun.misc.Unsafe { *; }
-keepattributes Signature
-keepattributes *Annotation*

# ---------------------------------------
# Flutter Specific
# ---------------------------------------
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# ---------------------------------------
# Keep your main activity
# ---------------------------------------
-keep class com.talnio.talnio.MainActivity { *; }

# Google Play Core / SplitCompat Fix
-keep class com.google.android.play.core.splitcompat.SplitCompatApplication { *; }
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
