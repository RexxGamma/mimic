import 'package:flutter/material.dart';
import 'package:mimic/appcolors.dart';

import 'Backend/providers/providermanager.dart';
import 'track.dart'; // Onesong
import 'playing_trackui.dart';
import 'Backend/metadatamanager.dart';

import 'package:provider/provider.dart';

class SongDiscography extends StatefulWidget {
  const SongDiscography({super.key, required this.artistId});

  /// Prefer passing just what you need over a whole untyped object.
  final String artistId;

  @override
  State<SongDiscography> createState() => _SongDiscographyState();
}

class _SongDiscographyState extends State<SongDiscography> {
  List<dynamic>? _songs;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mp = context.read<MetadataProvider>();
    try {
      final songs = await mp.getArtistDiscographySongs(widget.artistId);
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return CircularProgressIndicator(
        backgroundColor: AppColors.bordier,
        color: AppColors.accent,
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          'Failed to load discography',
          style: TextStyle(color: AppColors.text),
        ),
      );
    }
    final songs = _songs;
    if (songs == null || songs.isEmpty) {
      return const Center(child: Text('No songs'));
    }
    return Padding(
      padding: const EdgeInsets.all(10),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 110),
        itemCount: songs.length,
        itemBuilder: (context, index) => Onesong(song: songs[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            if (Metadatamanager.instance.currentSong != null)
              const PlayingTrackui(),
          ],
        ),
      ),
    );
  }
}
