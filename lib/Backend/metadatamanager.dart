import 'songdata.dart';
import 'package:flutter/foundation.dart';
import 'queuemanager.dart';
import 'providers/providermanager.dart';



class Metadatamanager extends ChangeNotifier {
  final mp = MetadataProvider(); 
  static final Metadatamanager instance = Metadatamanager._internal();

  SongInfo? _currentSong;
  SongInfo? get currentSong => _currentSong;

  int _requestId = 0;

  set currentSong(SongInfo? song) {
    _currentSong = song;
    notifyListeners();
    // Por defecto NO generamos radio en cambios automáticos
    _loadSong(song, generateRadio: false);
  }

  /// Método explícito para cuando el usuario SÍ quiere radio
  /// (por ejemplo al pulsar un botón "Iniciar radio").
  void startRadioFrom(SongInfo? song) {
    _currentSong = song;
    notifyListeners();
    _loadSong(song, generateRadio: true);
  }

  Future<void> _loadSong(
    SongInfo? song, {
    bool generateRadio = false,
  }) async {
    final requestId = ++_requestId;
    if (!generateRadio) {
      return;
    }

    if (song != null) {
      final index = _queueIndexOf(song);
      print("INDEX $index");
      if (index != -1) {
        QueueManager.instance.delete(index);
        return;
      }
    }

    QueueManager.instance.clear();

    try {
      final results = await searchradio(song ?? _currentSong);
      if (requestId != _requestId) return;
      if (results != null) {
        QueueManager.instance.addAll(results);
      }
    } catch (e) {
      debugPrint("Error al cargar radio: $e");
    }
  }


  int _queueIndexOf(SongInfo song) =>
      QueueManager.instance.queue.indexWhere((p) => p.id == song.id);
    
    Future<List<SongInfo>?> searchradio(SongInfo? song) async {
      if (song == null) return null;
      return await mp.getTrackRadio(song);
    }

    Metadatamanager._internal();
  }