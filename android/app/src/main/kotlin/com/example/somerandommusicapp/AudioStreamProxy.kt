package com.example.mimic

import android.util.Log
import fi.iki.elonen.NanoHTTPD
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.services.youtube.YoutubeParsingHelper
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamExtractor
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.util.concurrent.ConcurrentHashMap

class AudioStreamProxy(
    private val client: OkHttpClient,
    private val scope: CoroutineScope,
) : NanoHTTPD("127.0.0.1", 0) {

    companion object {
        private const val TAG = "AudioStreamProxy"

        @Volatile private var instance: AudioStreamProxy? = null
        private val streamCache = ConcurrentHashMap<String, AudioStream>()

        fun start(client: OkHttpClient, scope: CoroutineScope): Int {
            synchronized(this) {
                if (instance == null) {
                    val p = AudioStreamProxy(client, scope)
                    p.start(SOCKET_READ_TIMEOUT, false)
                    instance = p
                    Log.d(TAG, "Proxy arrancado en 127.0.0.1:${p.listeningPort}")
                }
            }
            return instance!!.listeningPort
        }

        fun stop() {
            synchronized(this) {
                instance?.stop()
                instance = null
                streamCache.clear()
            }
        }

        fun prefetch(videoId: String, extractor: StreamExtractor) {
            if (streamCache.containsKey(videoId)) return
            try {
                val best = extractor.audioStreams
                    .filter { it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }
                    .filter { !it.content.isNullOrBlank() }
                    .sortedWith(
                        compareByDescending<AudioStream> {
                            it.format?.mimeType?.contains("mp4") == true
                        }.thenByDescending { it.bitrate }
                    )
                    .firstOrNull()

                if (best != null) {
                    streamCache[videoId] = best
                    Log.d(TAG, "Prefetch OK: $videoId")

                    // Abrimos el socket TLS en background para que el
                    // player reuse el handshake ya hecho. Necesitamos
                    // pasar por la instancia porque client y
                    // streamingHeaders() no son estáticos.
                    instance?.scope?.launch(Dispatchers.IO) {
                        instance?.warmUpConnection(best)
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "Prefetch falló $videoId: ${t.message}")
            }
        }

        fun isCached(videoId: String): Boolean = streamCache.containsKey(videoId)
    }

    private fun streamingHeaders(): Map<String, String> {
        val ua = YoutubeParsingHelper.getVisionOsUserAgent(
            NewPipe.getPreferredLocalization()
        )
        return mapOf(
            "User-Agent" to ua,
            "Accept" to "*/*",
            "Referer" to "https://www.youtube.com/",
        )
    }

    /**
     * Abre el socket TLS a googlevideo haciendo un GET Range 0-0.
     * OkHttp lo deja en su pool y el primer request del player reusa
     * el handshake ya hecho (~500-800ms de ahorro por canción).
     */
    private fun warmUpConnection(stream: AudioStream) {
        try {
            val b = Request.Builder().url(stream.content)
            streamingHeaders().forEach { (k, v) -> b.header(k, v) }
            b.header("Range", "bytes=0-0")
            val resp = client.newCall(b.build()).execute()
            resp.close()
            Log.d(TAG, "TLS warm-up OK")
        } catch (_: Throwable) {
            // No es crítico: si falla, el player paga el handshake.
        }
    }

    private fun resolveStream(videoId: String): AudioStream? {
        streamCache[videoId]?.let { return it }
        synchronized(streamCache) {
            streamCache[videoId]?.let { return it }
            try {
                val extractor = ServiceList.YouTube.getStreamExtractor(
                    "https://www.youtube.com/watch?v=$videoId"
                )
                extractor.fetchPage()
                val best = extractor.audioStreams
                    .filter { it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }
                    .filter { !it.content.isNullOrBlank() }
                    .sortedWith(
                        compareByDescending<AudioStream> {
                            it.format?.mimeType?.contains("mp4") == true
                        }.thenByDescending { it.bitrate }
                    )
                    .firstOrNull()
                if (best != null) {
                    streamCache[videoId] = best
                    Log.d(TAG, "Extracción OK: $videoId")
                }
                return best
            } catch (t: Throwable) {
                Log.e(TAG, "Error extrayendo $videoId: ${t.message}", t)
                return null
            }
        }
    }

    private fun reExtractStream(videoId: String): AudioStream? {
        streamCache.remove(videoId)
        return resolveStream(videoId)
    }

    override fun serve(session: IHTTPSession): Response {
        val videoId = session.parameters["id"]?.firstOrNull()
            ?: return newFixedLengthResponse(
                Response.Status.BAD_REQUEST, "text/plain", "missing id"
            )

        val rangeHeader = session.headers["range"]?.trim()

        if (session.method == Method.HEAD) {
            val s = resolveStream(videoId) ?: return newFixedLengthResponse(
                Response.Status.NOT_FOUND, "text/plain", "no audio"
            )
            val resp = newFixedLengthResponse(
                Response.Status.OK, s.format?.mimeType ?: "audio/mp4", ""
            )
            resp.addHeader("Accept-Ranges", "bytes")
            return resp
        }

        val audio0 = resolveStream(videoId)
            ?: return newFixedLengthResponse(
                Response.Status.NOT_FOUND, "text/plain", "no audio"
            )

        var upstreamResp = openUpstream(audio0, rangeHeader)

        if (upstreamResp != null && upstreamResp.code == 403) {
            upstreamResp.close()
            Log.w(TAG, "403 — re-extrayendo $videoId")
            val fresh = reExtractStream(videoId)
            if (fresh != null) {
                upstreamResp = openUpstream(fresh, rangeHeader)
            }
        }

        if (upstreamResp == null) {
            return newFixedLengthResponse(
                Response.Status.INTERNAL_ERROR, "text/plain", "upstream exception"
            )
        }

        if (upstreamResp.code != 200 && upstreamResp.code != 206) {
            Log.e(TAG, "Upstream ${upstreamResp.code} para $videoId")
            val code = upstreamResp.code
            upstreamResp.close()
            return newFixedLengthResponse(
                Response.Status.INTERNAL_ERROR, "text/plain", "upstream $code"
            )
        }

        val status = if (upstreamResp.code == 206) Response.Status.PARTIAL_CONTENT
                     else Response.Status.OK
        val contentRange = upstreamResp.header("Content-Range")
        val mime = upstreamResp.header("Content-Type") ?: "audio/mp4"
        val length = upstreamResp.body?.contentLength() ?: -1L

        val respBody = upstreamResp.body
        if (respBody == null) {
            upstreamResp.close()
            return newFixedLengthResponse(
                Response.Status.INTERNAL_ERROR, "text/plain", "no body"
            )
        }

        val input = PipedInputStream(1024 * 256)
        val output = PipedOutputStream(input)

        Thread {
            try {
                respBody.byteStream().use { src ->
                    src.copyTo(output, 32 * 1024)
                }
            } catch (_: Throwable) {
                // El player cerró la conexión. Normal.
            } finally {
                try { output.close() } catch (_: Throwable) {}
                try { upstreamResp.close() } catch (_: Throwable) {}
            }
        }.apply { isDaemon = true }.start()

        return newFixedLengthResponse(status, mime, input, length).apply {
            addHeader("Accept-Ranges", "bytes")
            if (contentRange != null) addHeader("Content-Range", contentRange)
            addHeader("Cache-Control", "no-store")
        }
    }

    private fun openUpstream(
        audio: AudioStream,
        rangeHeader: String?,
    ): okhttp3.Response? {
        return try {
            val b = Request.Builder().url(audio.content)
            streamingHeaders().forEach { (k, v) -> b.header(k, v) }
            if (!rangeHeader.isNullOrBlank()) {
                b.header("Range", rangeHeader)
            }
            client.newCall(b.build()).execute()
        } catch (t: Throwable) {
            Log.e(TAG, "Upstream excepción: ${t.message}")
            null
        }
    }
}
