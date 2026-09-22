# Keep Dio and related networking classes
-keep class io.dio.** { *; }
-dontwarn io.dio.**

# Keep Play Core (referenced by Flutter's deferred components support,
# even if unused — its absence is a common cause of R8 stripping errors)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep flutter_secure_storage's Android implementation
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Keep JSON/serialization-related reflection targets
-keepattributes Signature
-keepattributes *Annotation*

# General Flutter/Android networking safety
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# Keep Firebase Cloud Messaging and its background message handler —
# release builds run with minification on, and R8 stripping any of this
# is a plausible reason a release APK (but not a debug run) fails to
# receive or display push notifications while backgrounded/terminated.
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**