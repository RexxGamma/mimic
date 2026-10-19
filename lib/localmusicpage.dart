import 'package:flutter/material.dart';
import 'package:mimic/appcolors.dart';

import 'Backend/localmusic.dart';
import 'Backend/metadatamanager.dart';
import 'playing_trackui.dart';
import 'track.dart';

class LocalMusicPage extends StatelessWidget {
  const LocalMusicPage({super.key});

  @override
  Widget build(BuildContext context) {
    final songs = LocalMusicManager.instance.songs;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        title: const Text(
          'On this device',
          style: TextStyle(
            color: AppColors.text,
            fontFamily: 'Adwaita',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Stack(
        children: [
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 70),
            itemCount: songs.length,
            itemBuilder: (_, i) => Onesong(
              key: ValueKey(songs[i].id),
              song: songs[i],
              albumtracks: songs,
            ),
          ),
          ListenableBuilder(
            listenable: Metadatamanager.instance,
            builder: (_, __) => Metadatamanager.instance.currentSong == null
                ? const SizedBox.shrink()
                : const Align(
                    alignment: Alignment.bottomCenter,
                    child: PlayingTrackui(),
                  ),
          ),
        ],
      ),
    );
  }
}
