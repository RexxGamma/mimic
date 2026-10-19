package com.example.mimic

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle

import com.ryanheise.audioservice.AudioServiceActivity

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class MainActivity : AudioServiceActivity() {

    private val bridgeScope =
        CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private lateinit var bridge: YouTubeBridge

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                1001
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bridge = YouTubeBridge(bridgeScope)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            YouTubeBridge.CHANNEL
        ).setMethodCallHandler { call, result ->
            bridge.handle(call, result)
        }

        // Warm-up del BotGuard de YouTube en background. No bloquea el
        // arranque; solo dispara el trabajo pesado del WebView para que
        // la primera búsqueda del usuario sea rápida.
        bridge.warmUp()
    }
}
