import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'Backend/audiomanager.dart';

class MimicAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayerManager manager;
  late final AudioPlayer player;

  MimicAudioHandler(this.manager) {
    player = manager.player;

    player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    player.sequenceStateStream.listen((state) {
      final items = state.sequence
          .map((s) => s.tag)
          .whereType<MediaItem>()
          .toList(growable: false);

      queue.add(items);

      final index = state.currentIndex;
      if (items.isNotEmpty && index != null && index < items.length) {
        mediaItem.add(items[index]); // ✅ usa el índice actual, no .first
      }
    });

    player.durationStream.listen((duration) {
      final current = mediaItem.value;
      if (duration != null && current != null && current.duration != duration) {
        mediaItem.add(current.copyWith(duration: duration));
      }
    });

    manager.addListener(_onManagerChanged);
  }

  void _onManagerChanged() {
    final s = playbackState.value;
    final expectedShuffle = manager.shuffle
        ? AudioServiceShuffleMode.all
        : AudioServiceShuffleMode.none;
    final expectedRepeat = manager.repeatTrack
        ? AudioServiceRepeatMode.one
        : AudioServiceRepeatMode.none;

    if (s.shuffleMode != expectedShuffle || s.repeatMode != expectedRepeat) {
      playbackState.add(
        s.copyWith(shuffleMode: expectedShuffle, repeatMode: expectedRepeat),
      );
    }
  }

  // Se llama al pulsar el botón shuffle de la notificación.
  // Delegamos en el manager (que ya sabe alternar el modo) en lugar de
  // escribir en un setter que puede no existir.
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final wantShuffle = shuffleMode != AudioServiceShuffleMode.none;
    if (manager.shuffle != wantShuffle) {
      manager.shuffle == !manager.shuffle;
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final wantRepeat = repeatMode == AudioServiceRepeatMode.one;
    if (manager.repeatTrack != wantRepeat) {
      manager.repeatTrack == !manager.repeatTrack;
    }
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
      shuffleMode: manager.shuffle
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
      repeatMode: manager.repeatTrack
          ? AudioServiceRepeatMode.one
          : AudioServiceRepeatMode.none,
    );
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (player.hasNext) manager.playnext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.hasPrevious) manager.playprevious();
  }

  @override
  Future<void> onTaskRemoved() async {
    manager.removeListener(_onManagerChanged);
    await super.onTaskRemoved();
  }
}
