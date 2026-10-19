package com.example.mimic

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.StreamInfoItem

class YouTubeBridge(private val scope: CoroutineScope) {

    companion object {
        const val CHANNEL = "com.example.somerandommusicapp/youtube"
        private const val TAG = "YoutubeBridge"

        @Volatile private var initialized = false
        @Volatile private var proxyPort: Int = 0
    }

    /**
     * Inicializa NewPipe y arranca el proxy local. Debe llamarse una
     * sola vez. Ya no es @Synchronized del companion porque necesita
     * acceso a `scope` (que es de la instancia).
     */
    private fun ensureInit() {
        synchronized(YouTubeBridge::class.java) {
            if (initialized) return
            val downloader = OkHttpDownloader()
            NewPipe.init(downloader)
            proxyPort = AudioStreamProxy.start(downloader.client, scope)
            initialized = true

            try {
                val wv = android.webkit.WebView.getCurrentWebViewPackage()
                Log.d(TAG, "WebView: ${wv?.packageName} v${wv?.versionName}")
            } catch (_: Throwable) {}
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    /** Dispara el BotGuard en background al arrancar la app. */
    fun warmUp() {
        scope.launch(Dispatchers.IO) {
            try {
                ensureInit()
                val extractor = ServiceList.YouTube.getSearchExtractor("music")
                extractor.fetchPage()
                Log.d(TAG, "Warm-up OK")
            } catch (t: Throwable) {
                Log.w(TAG, "Warm-up falló: ${t.message}")
            }
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "search" -> handleSearch(call, result)
            "getAudioStreams" -> handleGetAudioStreams(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleSearch(call: MethodCall, result: MethodChannel.Result) {
        val query = call.argument<String>("query")
        val limit = call.argument<Int>("limit") ?: 15

        if (query.isNullOrBlank()) {
            result.error("BAD_ARGS", "Falta query", null)
            return
        }

        scope.launch(Dispatchers.IO) {
            try {
                ensureInit()
                val items = search(query, limit)
                mainHandler.post { result.success(items) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("SEARCH_FAILED", e.message ?: e.toString(), null)
                }
            }
        }
    }

    private fun handleGetAudioStreams(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val videoUrl = call.argument<String>("videoUrl")
        if (videoUrl.isNullOrBlank()) {
            result.error("BAD_ARGS", "Falta videoUrl", null)
            return
        }

        scope.launch(Dispatchers.IO) {
            try {
                ensureInit()
                val streams = getAudioStreams(videoUrl)
                mainHandler.post { result.success(streams) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("STREAMS_FAILED", e.message ?: e.toString(), null)
                }
            }
        }
    }

    private fun search(query: String, limit: Int): List<Map<String, Any?>> {
        val extractor = ServiceList.YouTube.getSearchExtractor(query)
        extractor.fetchPage()

        val out = mutableListOf<Map<String, Any?>>()
        for (item in extractor.initialPage.items) {
            if (out.size >= limit) break
            if (item is StreamInfoItem) {
                out.add(
                    mapOf(
                        "url" to item.url,
                        "title" to item.name,
                        "uploader" to item.uploaderName,
                        "durationSeconds" to item.duration,
                    )
                )
            }
        }
        return out
    }

    private fun getAudioStreams(videoUrl: String): List<Map<String, Any?>> {
        val videoId = videoUrl
            .substringAfter("v=")
            .substringBefore("&")
            .substringBefore("?")

        // Extrae el stream y dispara la descarga completa en background.
        // Cuando el player toque el proxy, ya estará en RAM.
        try {
            if (!AudioStreamProxy.isCached(videoId)) {
                val extractor = ServiceList.YouTube.getStreamExtractor(videoUrl)
                extractor.fetchPage()
                AudioStreamProxy.prefetch(videoId, extractor)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Prefetch en bridge falló: ${t.message}")
        }

        return listOf(
            mapOf(
                "url" to "http://127.0.0.1:$proxyPort/stream?id=$videoId",
                "mimeType" to "audio/mp4",
                "bitrate" to 128000,
                "headers" to emptyMap<String, String>(),
            )
        )
    }
}
