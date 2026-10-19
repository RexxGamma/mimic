// Backend/chunked_downloader.dart
//
// Descarga rápida de audio: trozos de 1 MiB con Range, 4 en paralelo.
// Independiente del proveedor: solo necesita url + headers.
// Un GET único a googlevideo suele quedar limitado a ~velocidad realtime.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mimic/Backend/providers/streaming/streamingmanager.dart';
import 'package:mimic/Backend/songdata.dart';

/// Descarga el audio de [song] a [destPath] usando el proveedor activo.
///  • Intenta descarga por trozos en paralelo.
///  • 403 (URL expirada) → pide URL fresca y reintenta una vez.
///  • Cualquier otro fallo del modo por trozos (server sin Range, HLS…)
///    → cae a dio.download, como antes.
Future<void> downloadSongAudio(
  SongInfo song,
  String destPath, {
  void Function(int received, int total)? onProgress,
}) async {
  bool is403(Object e) => e is HttpException && e.message.contains('403');

  Future<void> attempt({required bool refresh}) async {
    final r = await StreamingManager.instance.getResolvedStream(
      song,
      forceRefresh: refresh,
    );
    if (r == null || r.url.isEmpty) {
      throw Exception('No URL para ${song.name}');
    }
    try {
      await ChunkedDownloader.download(
        r.url,
        destPath,
        headers: r.headers,
        onProgress: onProgress,
      );
    } catch (e) {
      if (is403(e)) rethrow;
      debugPrint('ChunkedDownloader falló ($e) — fallback a dio');
      await Dio().download(
        r.url,
        destPath,
        options: Options(headers: r.headers.isNotEmpty ? r.headers : null),
      );
    }
  }

  try {
    await attempt(refresh: false);
  } catch (e) {
    if (!is403(e)) rethrow;
    await attempt(refresh: true);
  }
}

class _Chunk {
  final Uint8List bytes;
  final int? total; // tamaño total según Content-Range
  final bool full; // el server ignoró Range y mandó todo (HTTP 200)
  _Chunk(this.bytes, this.total, this.full);
}

class ChunkedDownloader {
  static const _chunkSize = 1024 * 1024; // 1 MiB
  static const _workers = 4;
  static const _maxRetries = 2;
  static const _ioTimeout = Duration(seconds: 10);

  /// Escribe en `destPath.part` y renombra al terminar.
  /// Lanza [HttpException] con "403" si la URL expiró.
  static Future<void> download(
    String url,
    String destPath, {
    Map<String, String> headers = const {},
    void Function(int received, int total)? onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 15)
      ..maxConnectionsPerHost = _workers;

    final part = File('$destPath.part');
    RandomAccessFile? raf;

    try {
      // 1. Primer trozo: de paso nos dice el tamaño total.
      final first = await _fetchWithRetry(
        client,
        url,
        headers,
        0,
        _chunkSize - 1,
      );

      // Si el server ignoró Range y devolvió una playlist HLS, esto no es
      // audio: que lo maneje el fallback.
      if (first.full &&
          first.bytes.length > 7 &&
          String.fromCharCodes(first.bytes.sublist(0, 7)) == '#EXTM3U') {
        throw HttpException('Formato no soportado (HLS)');
      }

      final total = first.total ?? first.bytes.length;

      raf = await part.open(mode: FileMode.write);
      final file = raf;

      // Escrituras en cola: un solo RandomAccessFile compartido.
      Future<void> lock = Future.value();
      Future<void> write(int pos, Uint8List b) {
        lock = lock.then((_) async {
          await file.setPosition(pos);
          await file.writeFrom(b);
        });
        return lock;
      }

      var received = 0;
      await write(0, first.bytes);
      received += first.bytes.length;
      onProgress?.call(received, total);

      // 2. Resto de trozos con un pool de workers.
      if (!first.full && first.bytes.length < total) {
        final starts = <int>[
          for (var s = first.bytes.length; s < total; s += _chunkSize) s,
        ];
        var next = 0;
        var failed = false;

        Future<void> worker() async {
          while (!failed && next < starts.length) {
            final start = starts[next++];
            final end = math.min(start + _chunkSize, total) - 1;
            try {
              final c = await _fetchWithRetry(client, url, headers, start, end);
              await write(start, c.bytes);
              received += c.bytes.length;
              onProgress?.call(received, total);
            } catch (_) {
              failed = true;
              rethrow;
            }
          }
        }

        await Future.wait(List.generate(_workers, (_) => worker()));
      }

      await lock;
      await file.close();
      raf = null;

      if (received != total) {
        throw HttpException('Descarga incompleta: $received/$total');
      }
      await part.rename(destPath);
    } catch (e) {
      try {
        await raf?.close();
        if (await part.exists()) await part.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<_Chunk> _fetchWithRetry(
    HttpClient client,
    String url,
    Map<String, String> headers,
    int start,
    int end,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _fetch(client, url, headers, start, end);
      } on HttpException catch (e) {
        // 403 = URL expirada/inválida: reintentar igual no sirve.
        if (e.message.contains('403') || attempt >= _maxRetries) rethrow;
      } on TimeoutException {
        if (attempt >= _maxRetries) rethrow;
      } on SocketException {
        if (attempt >= _maxRetries) rethrow;
      }
      debugPrint('ChunkedDownloader: reintentando bytes=$start-$end');
    }
  }

  static Future<_Chunk> _fetch(
    HttpClient client,
    String url,
    Map<String, String> headers,
    int start,
    int end,
  ) async {
    final req = await client.getUrl(Uri.parse(url));
    headers.forEach((k, v) => req.headers.set(k, v));
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');

    final resp = await req.close().timeout(_ioTimeout);
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      await resp.drain<void>();
      throw HttpException('HTTP ${resp.statusCode}', uri: req.uri);
    }

    final builder = BytesBuilder(copy: false);
    await for (final c in resp.timeout(_ioTimeout)) {
      builder.add(c);
    }

    int? total;
    final cr = resp.headers.value(HttpHeaders.contentRangeHeader);
    if (cr != null) {
      final slash = cr.lastIndexOf('/');
      if (slash != -1) total = int.tryParse(cr.substring(slash + 1));
    }

    return _Chunk(builder.takeBytes(), total, resp.statusCode == 200);
  }
}
