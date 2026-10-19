package com.example.mimic

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request as NPRequest
import org.schabi.newpipe.extractor.downloader.Response as NPResponse
import java.util.concurrent.TimeUnit

class OkHttpDownloader : Downloader() {

    companion object {
        const val USER_AGENT =
            "com.google.visionos.youtube/1.02" +
            "(RealityDevice14,1; U; CPU visionOS 25_6_0 like Mac OS X; es-CO)"
    }

    // Sin private: el AudioStreamProxy lo necesita para descargar los bytes.
    val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .connectionPool(okhttp3.ConnectionPool(8, 5, TimeUnit.MINUTES))
        .build()

    override fun execute(request: NPRequest): NPResponse {
        val builder = Request.Builder().url(request.url())

        var hasUserAgent = false
        request.headers().forEach { (key, values) ->
            values.forEach { value ->
                builder.addHeader(key, value)
                if (key.equals("User-Agent", ignoreCase = true)) {
                    hasUserAgent = true
                }
            }
        }

        if (!hasUserAgent) {
            builder.header("User-Agent", USER_AGENT)
        }

        val body = request.dataToSend()?.toRequestBody(
            "application/json".toMediaType()
        )

        val okReq = when (request.httpMethod()) {
            "GET" -> builder.get().build()
            "POST" -> builder.post(body ?: "".toRequestBody()).build()
            "HEAD" -> builder.head().build()
            "DELETE" -> builder.delete(body).build()
            else -> builder.method(request.httpMethod(), body).build()
        }

        client.newCall(okReq).execute().use { resp ->
            return NPResponse(
                resp.code,
                resp.message,
                resp.headers.toMultimap(),
                resp.body?.string() ?: "",
                resp.request.url.toString()
            )
        }
    }
}
