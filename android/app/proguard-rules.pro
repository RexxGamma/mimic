# ── JavaBeans (tuyo) ─────────────────────────────────────────
-dontwarn java.beans.BeanDescriptor
-dontwarn java.beans.BeanInfo
-dontwarn java.beans.IntrospectionException
-dontwarn java.beans.Introspector
-dontwarn java.beans.PropertyDescriptor

# ── Play Core (deferred components de Flutter) ────────────────
# Necesario porque activamos R8 (isMinifyEnabled = true) y Flutter
# referencia estas clases aunque tu app no incluya la librería.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# ── audio_service (tuyo) ──────────────────────────────────────
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.audioservice.AudioService { *; }
-keep class com.ryanheise.audioservice.MediaButtonReceiver { *; }

# ── just_audio (tuyo) ─────────────────────────────────────────
-keep class com.ryanheise.just_audio.** { *; }

# ── NewPipeExtractor (lo usas para streaming) ─────────────────
-keep class org.schabi.newpipe.extractor.** { *; }

# ── OkHttp (dependencia de NewPipe) ───────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**

# ── Flutter embedding (tuyo) ──────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }