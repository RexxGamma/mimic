import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'songdata.dart';

class QueueManager extends ChangeNotifier {
  QueueManager._internal();

  static final QueueManager instance = QueueManager._internal();

  final List<SongInfo> _queue = [];
  // historial de canciones que ya salieron de la cola
  final List<SongInfo> _history = [];

  late final UnmodifiableListView<SongInfo> _queueView = UnmodifiableListView(
    _queue,
  );
  //vista inmutable del historial
  late final UnmodifiableListView<SongInfo> _historyView = UnmodifiableListView(
    _history,
  );

  UnmodifiableListView<SongInfo> get queue => _queueView;
  // getter público
  UnmodifiableListView<SongInfo> get history => _historyView;

  bool get isEmpty => _queue.isEmpty;
  int get length => _queue.length;
  //atajo útil
  bool get hasHistory => _history.isNotEmpty;

  SongInfo? randomNext() {
    if (_queue.isEmpty) return null;
    final random = Random();
    final index = random.nextInt(_queue.length);
    final song = _queue.removeAt(index);
    _history.add(song);
    notifyListeners();
    return song;
  }

  void addAll(Iterable<SongInfo> songs) {
    _queue.addAll(songs);
    notifyListeners();
  }

  SongInfo? next() {
    if (_queue.isEmpty) return null;
    final song = _queue.removeAt(0);
    _history.add(song);
    notifyListeners();
    return song;
  }

  SongInfo? previous() {
    if (_history.length < 2) return null;

    final current = _history.removeLast();
    _queue.insert(0, current);

    final prev = _history.removeLast();
    notifyListeners();
    return prev;
  }

  /// Devuelve la siguiente canción SIN sacarla de la cola.
  SongInfo? peekNext() {
    if (_queue.isEmpty) return null;
    return _queue.first;
  }

  /// Devuelve la canción `offset` posiciones adelante, sin sacarla.
  /// `peekAfter(0)` == `peekNext()`.
  SongInfo? peekAfter(int offset) {
    if (offset >= _queue.length) return null;
    return _queue[offset];
  }

  bool moveToFront(SongInfo song) {
    final i = _queue.indexWhere((p) => p.id == song.id);
    if (i <= 0) return i == 0 ? true : false;

    final nueva = List<SongInfo>.from(_queue);
    final t = nueva.removeAt(i);
    nueva.insert(0, t);

    _queue
      ..clear()
      ..addAll(nueva);

    notifyListeners();
    return true;
  }

  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final song = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, song);
  }

  void add(SongInfo song) {
    _queue.add(song);
    notifyListeners();
  }

  void delete(int index) {
    _queue.removeAt(index);
    notifyListeners();
  }

  void clear() {
    _queue.clear();
    notifyListeners();
  }
}

