import 'package:flutter/material.dart';
import 'package:mimic/appcolors.dart';
import 'package:provider/provider.dart';

import 'Backend/metadatamanager.dart';
import 'playing_trackui.dart';
import 'libraryabumView.dart';
import 'Backend/providers/providermanager.dart';
import 'Backend/recordtypelabels.dart';

class Fulldiscographyview extends StatefulWidget {
  const Fulldiscographyview({super.key, required this.artistid});
  final String artistid;

  @override
  State<Fulldiscographyview> createState() => _FulldiscographyviewState();
}

class _FulldiscographyviewState extends State<Fulldiscographyview> {
  List albumlist = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _searchAlbums();
  }

  Future<void> _searchAlbums() async {
    // El provider de la app, no una instancia nueva
    final mp = context.read<MetadataProvider>();

    try {
      final albums = await mp.getArtistDiscography(widget.artistid);
      if (!mounted) return;
      setState(() {
        albumlist = albums;
        _loading = false;
        _failed = false;
      });
    } catch (e) {
      debugPrint('Error cargando discografía: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Widget _centerText(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 16,
      color: AppColors.text2,
      fontFamily: "Adwaita",
      decoration: TextDecoration.none,
    ),
  );

  Widget _body() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          backgroundColor: AppColors.bordier,
          color: AppColors.accent,
        ),
      );
    }

    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _centerText("Couldn't load the discography"),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _failed = false;
                });
                _searchAlbums();
              },
              child: const Text(
                "Retry",
                style: TextStyle(color: AppColors.text),
              ),
            ),
          ],
        ),
      );
    }

    if (albumlist.isEmpty) {
      return Center(child: _centerText("No albums found"));
    }

    return GridView.builder(
      // Padding abajo para que el reproductor no tape la última fila
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 110),
      itemCount: albumlist.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        childAspectRatio: 1 / 1.33,
        mainAxisSpacing: 3,
      ),
      itemBuilder: (context, index) {
        final album = albumlist[index];
        return AlbumView(data: album, label: recordTypeLabel(album.recordType));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _body()),
            if (Metadatamanager.instance.currentSong != null)
              Align(
                alignment: AlignmentGeometry.bottomCenter,
                child: PlayingTrackui(),
              ),
          ],
        ),
      ),
    );
  }
}
