import 'package:just_audio/just_audio.dart';
import 'package:mimic/Backend/providers/streaming/streamingmanager.dart';
import 'package:mimic/Backend/songdata.dart';

import 'queuemanager.dart';
import 'metadatamanager.dart';
import 'settings.dart';

import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';

class AudioPlayerManager extends ChangeNotifier {
  AudioPlayerManager._internal() : _streaming = StreamingManager.instance {
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.ready) {
        debugPrint('PLAY: player READY');
      }
      notifyListeners();

      if (state.processingState == ProcessingState.completed) {
        onSongFinished();
      }
    });
  }

  static final AudioPlayerManager instance = AudioPlayerManager._internal();

  bool _shuffle = false;
  bool _repeatTrack = false;

  bool get shuffle => _shuffle;
  bool get repeatTrack => _repeatTrack;

  set shuffle(bool value) {
    _shuffle = value;
    notifyListeners();
  }

  set repeatTrack(bool value) {
    _repeatTrack = value;
    notifyListeners();
  }

  final AudioPlayer player = AudioPlayer();
  final StreamingManager _streaming;

  int _requestId = 0;

  bool get isPlaying => player.playing;

  Icon consultPlayerState() {
    return player.playing
        ? const Icon(Icons.pause)
        : const Icon(Icons.play_arrow);
  }

  // ── Crossfade ────────────────────────────────────────────────
  //
  // Con un solo AudioPlayer no se pueden solapar dos canciones, así que el
  // "crossfade" es un fundido: la canción baja de volumen en sus últimos N
  // segundos y la siguiente sube desde 0 en sus primeros N segundos.
  // El volumen es SIEMPRE función de la posición, así que si haces seek o
  // pausas a mitad del fundido, el volumen se recalcula solo.

  Timer? _fader;
  double _lastVolume = 1.0;
  bool _pendingAutoFade =
      false; // la próxima canción arranca por transición automática
  bool _fadeInActive = false; // la canción actual está en su fade-in

  bool get _hasNext => _repeatTrack || QueueManager.instance.peekNext() != null;

  void _startFader({required bool fadeIn}) {
    _fader?.cancel();
    _fadeInActive = fadeIn;
    _fader = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _fadeTick(),
    );
  }

  void _stopFader() {
    _fader?.cancel();
    _fader = null;
    _fadeInActive = false;
  }

  Future<void> _setVolumeNow(double v) async {
    _lastVolume = v;
    await player.setVolume(v);
  }

  void _applyVolume(double v) {
    v = v.clamp(0.0, 1.0);
    if (v == _lastVolume) return;
    // Evita saturar al reproductor con cambios imperceptibles (salvo 0 y 1)
    if ((v - _lastVolume).abs() < 0.01 && v != 0.0 && v != 1.0) return;
    _lastVolume = v;
    unawaited(player.setVolume(v));
  }

  void _fadeTick() {
    if (!player.playing) return;
    if (player.processingState != ProcessingState.ready) return;

    final setting = AppSettings.instance.crossfadeSeconds * 1000;
    if (setting <= 0) {
      _applyVolume(1.0); // por si se desactivó a mitad de un fundido
      return;
    }

    final total = player.duration;
    if (total == null) return;

    final totalMs = total.inMilliseconds;
    final posMs = player.position.inMilliseconds;

    // En canciones cortas el fundido no puede pasar de la mitad
    final fadeMs = math.min(setting, totalMs ~/ 2);
    if (fadeMs <= 0) return;

    var vol = 1.0;

    // Fade-out: solo si hay una canción que sigue
    final remaining = totalMs - posMs;
    if (remaining < fadeMs && _hasNext) {
      final t = (remaining / fadeMs).clamp(0.0, 1.0);
      vol = math.sin(t * math.pi / 2); // curva de potencia constante
    }

    // Fade-in
    if (_fadeInActive) {
      if (posMs >= fadeMs) {
        _fadeInActive = false;
      } else {
        final t = (posMs / fadeMs).clamp(0.0, 1.0);
        vol = math.min(vol, math.sin(t * math.pi / 2));
      }
    }

    _applyVolume(vol);
  }

  // ── Queue ────────────────────────────────────────────────────

  void onSongFinished() {
    if (_repeatTrack) {
      final currentSong = Metadatamanager.instance.currentSong;
      if (currentSong != null) {
        _pendingAutoFade = true;
        play(currentSong);
      }
      return;
    }

    SongInfo? nextSong;
    if (_shuffle) {
      nextSong = QueueManager.instance.randomNext();
    } else {
      nextSong = QueueManager.instance.next();
    }

    if (nextSong != null) {
      Metadatamanager.instance.currentSong = nextSong;
      _pendingAutoFade = true;
      play(nextSong);
    }
  }

  void playnext() {
    SongInfo? nextSong = QueueManager.instance.next();
    if (nextSong != null) {
      Metadatamanager.instance.currentSong = nextSong;
      play(nextSong);
    }
  }

  void playprevious() {
    SongInfo? previous = QueueManager.instance.previous();
    if (previous != null) {
      Metadatamanager.instance.currentSong = previous;
      play(previous);
    }
  }

  // ── PlayTrack ────────────────────────────────────────────────

  int _consecutiveFailures = 0;
  static const _maxConsecutiveFailures = 3;

  Future<void> play(SongInfo song) async {
    final requestId = ++_requestId;

    // ¿Esta canción arranca por una transición automática? (ver onSongFinished)
    // Los cambios manuales (next, previous, tocar una canción) no hacen fade-in.
    final fadeIn = _pendingAutoFade;
    _pendingAutoFade = false;

    try {
      await _playInternal(
        song,
        requestId,
        forceRefreshUrl: false,
        fadeIn: fadeIn,
      );
      _consecutiveFailures = 0;
    } on PlayerException catch (e, stackTrace) {
      final isSourceError =
          e.code == 0 || (e.message ?? '').contains('Source error');
      final isStreaming = song.downloadPath == null;

      if (isSourceError && isStreaming && requestId == _requestId) {
        debugPrint(
          'AudioPlayerManager: source error (posible 403) en ${song.name} '
          '— reintentando con URL fresca…',
        );
        try {
          await _playInternal(
            song,
            requestId,
            forceRefreshUrl: true,
            fadeIn: fadeIn,
          );
          _consecutiveFailures = 0;
          return;
        } catch (e2, st2) {
          debugPrint(
            'AudioPlayerManager: reintento falló para ${song.name}: $e2\n$st2',
          );
        }
      }
      debugPrint(
        'Error de just_audio reproduciendo ${song.name}: $e\n$stackTrace',
      );
      if (requestId == _requestId) _onPlaybackFailed();
    } catch (e, stackTrace) {
      debugPrint('Error reproduciendo ${song.name}: $e\n$stackTrace');
      if (requestId == _requestId) _onPlaybackFailed();
    }
  }

  /// Se llama cuando `play()` falla. Avanza a la siguiente canción
  /// automáticamente, salvo que ya hayan fallado demasiadas seguidas.
  void _onPlaybackFailed() {
    _consecutiveFailures++;
    debugPrint(
      'AudioPlayerManager: playback falló (${_consecutiveFailures}/$_maxConsecutiveFailures)',
    );

    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      debugPrint(
        'AudioPlayerManager: demasiados fallos seguidos — parando auto-skip',
      );
      _consecutiveFailures = 0;
      return;
    }

    final nextSong = QueueManager.instance.next();
    if (nextSong == null) {
      debugPrint('AudioPlayerManager: queue vacío, nada que saltar');
      _consecutiveFailures = 0;
      return;
    }

    Metadatamanager.instance.currentSong = nextSong;
    debugPrint('AudioPlayerManager: saltando a "${nextSong.name}"');
    play(nextSong);
  }

  Future<void> _playInternal(
    SongInfo song,
    int requestId, {
    required bool forceRefreshUrl,
    required bool fadeIn,
  }) async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    debugPrint('PLAY: [0ms] inicio ${song.name}');

    // Cualquier fundido de la canción anterior termina aquí
    _stopFader();
    final useFadeIn = fadeIn && AppSettings.instance.crossfadeSeconds > 0;
    await _setVolumeNow(useFadeIn ? 0.0 : 1.0);

    final bannerPath = song.downloadBannerPath;
    final hasLocalBanner =
        bannerPath != null && await File(bannerPath).exists();

    final mediaItem = MediaItem(
      id: song.id,
      title: song.name,
      artist: song.artists.map((a) => a.name).join(', '),
      album: song.album?.toString() ?? '',
      duration: song.duration,
      artUri: hasLocalBanner
          ? Uri.file(bannerPath)
          : (song.thumbnails.isNotEmpty
                ? Uri.parse(song.thumbnails.last.url)
                : null),
    );

    final AudioSource source;

    final localPath = song.downloadPath;
    debugPrint("LOCALPATH : $localPath");

    if (localPath != null) {
      source = AudioSource.uri(Uri.file(localPath), tag: mediaItem);
    } else {
      final resolved = await _streaming.getResolvedStream(
        song,
        forceRefresh: forceRefreshUrl,
      );

      if (requestId != _requestId) {
        debugPrint(
          'PLAY: request $requestId cancelado por $_requestId (tras resolver)',
        );
        return;
      }
      debugPrint(
        'PLAY: resolved=${resolved?.url} headers=${resolved?.headers}',
      );

      if (resolved == null || resolved.url.isEmpty) {
        throw StateError('No se obtuvo una URL de audio para ${song.name}');
      }

      debugPrint(
        'PLAY: [${DateTime.now().millisecondsSinceEpoch - t0}ms] URL obtenida',
      );
      source = AudioSource.uri(
        Uri.parse(resolved.url),
        tag: mediaItem,
        headers: resolved.headers.isNotEmpty ? resolved.headers : null,
      );
    }

    await player.setAudioSource(source);
    debugPrint(
      'PLAY: [${DateTime.now().millisecondsSinceEpoch - t0}ms] setAudioSource OK',
    );

    if (requestId != _requestId) return;

    // Antes de play(): el temporizador no depende de cuándo regrese ese Future
    _startFader(fadeIn: useFadeIn);

    await player.play();
    debugPrint(
      'PLAY: [${DateTime.now().millisecondsSinceEpoch - t0}ms] play() OK',
    );
    notifyListeners();

    _preloadNext();
  }

  /// Precarga las próximas 2 canciones de la cola en background. Se
  /// llama después de player.play() para que no retrase el arranque
  /// del audio actual.
  ///
  /// Importante: cuando este método corre, la canción actual YA fue
  /// sacada de `_queue` por `next()` (o `randomNext()`), así que
  /// `_queue.first` es la canción que sonará después.
  void _preloadNext() {
    if (_shuffle) return;

    final next = QueueManager.instance.peekNext();
    if (next == null) return;
    if (next.downloadPath != null) return;

    final after = QueueManager.instance.peekAfter(1);
    final toPreload = <SongInfo>[next, if (after != null) after];

    debugPrint(
      'PLAY: _preloadNext → ${toPreload.map((s) => s.name).join(", ")}',
    );
    _streaming.preload(toPreload);
  }

  Future<void> stop() async {
    _stopFader();
    await player.stop();
    await _setVolumeNow(1.0);
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _requestId++;
    _stopFader();
    await player.dispose();
    super.dispose();
  }
}
