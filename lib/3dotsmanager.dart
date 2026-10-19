enum SongSource {
  album,
  exterior,
  playlist,
  player,
  queue
}



class SongContextManager {
  static int currentPlaylistId = -1;
  static final List<SongSource> _stack = [];

  static SongSource get current =>
      _stack.isEmpty ? SongSource.exterior : _stack.last;

  static void push(SongSource source) {
    _stack.add(source);
  }

  static void pop() {
    if (_stack.isNotEmpty) {
      _stack.removeLast();
    }
  }
}