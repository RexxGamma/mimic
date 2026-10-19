#!/bin/bash

# Script para migrar de just_audio_background a audio_service
# Añade soporte para botones de shuffle y repeat en la notificación.

set -e

# 1. Actualizar pubspec.yaml
echo "Actualizando pubspec.yaml..."
flutter pub remove just_audio_background
flutter pub add audio_service just_audio

# 2. Crear el archivo del AudioHandler
echo "Creando lib/audio_handler.dart..."
mkdir -p lib
cat > lib/audio_handler.dart << 'EOF'
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

// El AudioHandler es el puente entre tu UI y el servicio en segundo plano.
// Define todos los controles que aparecerán en la notificación.
class MimicAudioHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();

  MimicAudioHandler() {
    // Reenvía los eventos del player a audio_service
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Sincroniza la cola de reproducción
    _player.sequenceStateStream.listen((sequenceState) {
      final sequence = sequenceState?.sequence ?? [];
      queue.add(sequence);
    });
  }

  // Transforma el estado del player al formato que espera audio_service
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        // Controles que aparecerán en la notificación.
        // El orden aquí es el orden en la notificación (de izquierda a derecha).
        MediaControl.shuffle( // Botón de Shuffle
          onPressed: () => setShuffleMode(AudioServiceShuffleMode.all),
        ),
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.repeat( // Botón de Repeat
          onPressed: () => setRepeatMode(AudioServiceRepeatMode.all),
        ),
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [1, 2, 3], // Botones para la vista compacta
      processingState: {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  // --- Métodos de control expuestos a la UI ---

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  // --- Implementación de Shuffle y Repeat ---

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    // Mapea el modo de audio_service al modo de just_audio
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    await _player.setShuffleModeEnabled(enabled);
    
    // Actualiza el estado para que la UI y la notificación reflejen el cambio
    playbackState.add(playbackState.value.copyWith(
      shuffleMode: shuffleMode,
    ));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    // Mapea el modo de audio_service al modo de just_audio
    final loopMode = {
      AudioServiceRepeatMode.none: LoopMode.off,
      AudioServiceRepeatMode.one: LoopMode.one,
      AudioServiceRepeatMode.all: LoopMode.all,
    }[repeatMode]!;
    
    await _player.setLoopMode(loopMode);
    
    playbackState.add(playbackState.value.copyWith(
      repeatMode: repeatMode,
    ));
  }

  // --- Carga de la playlist ---

  @override
  Future<void> loadPlaylist(List<MediaItem> items) async {
    final playlist = ConcatenatingAudioSource(
      children: items.map((item) => AudioSource.uri(
        Uri.parse(item.extras!['url'] as String),
        tag: item,
      )).toList(),
    );
    await _player.setAudioSource(playlist);
  }
}
EOF

echo "Migración completada. Revisa lib/audio_handler.dart y actualiza tu main.dart."
