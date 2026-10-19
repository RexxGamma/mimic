import 'package:flutter/material.dart';

import 'menu.dart';

import 'package:provider/provider.dart';

import 'Backend/playlistsmanager.dart';
import 'Backend/songlisttoplay.dart';
import 'Backend/followedartistdb.dart';
import 'Backend/providers/providermanager.dart';
import 'Backend/settings.dart';
import 'Backend/localmusic.dart';
import 'Backend/adaptivepalette.dart';

import 'package:audio_service/audio_service.dart';

import 'audio_handler.dart';
import 'Backend/audiomanager.dart';
import 'Backend/albumsSaved.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppSettings.instance.load();
  AdaptiveTheme.init();

  await LocalMusicManager.instance.init();

  final songDb = SongDatabase();
  await songDb.init();
  // main.dart, después de WidgetsFlutterBinding.ensureInitialized()
  // Fire-and-forget: no bloquea el arranque.
  Future.microtask(() async {
    try {
      // Cualquier query sirve; solo queremos disparar el BotGuard JS.
    } catch (_) {}
  });
  await AudioService.init(
    builder: () {
      final h = MimicAudioHandler(AudioPlayerManager.instance);
      return h;
    },
    config: AudioServiceConfig(
      androidNotificationChannelId: 'mimic.audio',
      androidNotificationChannelName: 'mimic',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/logowhite',
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppDatabase()..loadPlaylists()),
        ChangeNotifierProvider<SongDatabase>.value(value: songDb),
        ChangeNotifierProvider(create: (_) => AlbumDatabase()),
        ChangeNotifierProvider(create: (_) => ArtistDatabase()),
        ChangeNotifierProvider(create: (_) => MetadataProvider()),
      ],
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(fontFamily: 'Adwaita'),
      home: Scaffold(body: Center(child: MainMenu())),
    );
  }
}
