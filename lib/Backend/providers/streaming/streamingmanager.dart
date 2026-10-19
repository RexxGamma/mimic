import 'package:mimic/Backend/songdata.dart';
import 'package:mimic/Backend/providers/streaming/youtube.dart';
import 'package:mimic/Backend/providers/streaming/soundcloud.dart';

import '../privdersenums.dart';

class StreamingManager {
  StreamingManager._();

  static final StreamingManager instance = StreamingManager._();

  StreamingProvider _provider = StreamingProvider.youtube;

  StreamingProvider get provider => _provider;

  void configure({required StreamingProvider provider}) {
    _provider = provider;
  }

  Future<String?> getUrl(SongInfo song) async {
    switch (song.streamingSource) {
      case StreamingProvider.youtube:
        return await youtubeApi.resolveStreamUrl(song);

      case StreamingProvider.soundcloud:
        return await soundcloudApi.resolveStreamUrl(song);

      case StreamingProvider.local:
        // Los archivos locales se reproducen desde downloadPath, no hay URL.
        print('StreamingManager: ${song.name} es local, no se resuelve URL');
        return null;
    }
  }

  Future<ResolvedStream?> getResolvedStream(
    SongInfo song, {
    bool forceRefresh = false,
  }) async {
    switch (song.streamingSource) {
      case StreamingProvider.youtube:
        return youtubeApi.resolveStreamInfo(song, forceRefresh: forceRefresh);

      case StreamingProvider.soundcloud:
        final url = await soundcloudApi.resolveStreamUrl(song);
        if (url == null || url.isEmpty) return null;
        return ResolvedStream(url: url, isLikelyOriginal: false);
      case StreamingProvider.local:
        return null;
    }
  }

  /// Precarga en background. Delega al resolver correspondiente según
  /// el `streamingSource` de cada canción. Fire-and-forget.
  void preload(Iterable<SongInfo> songs) {
    for (final s in songs) {
      print('StreamingManager.preload: ${s.name} (${s.streamingSource})');
      switch (s.streamingSource) {
        case StreamingProvider.youtube:
          youtubeApi.preload([s]);
        case StreamingProvider.soundcloud:
          soundcloudApi.preload([s]);
        case StreamingProvider.local:
          return null;
      }
    }
  }
}
