import 'package:flutter/material.dart';
import 'package:mimic/appcolors.dart';
import 'package:mimic/playlistlist.dart';
import 'package:provider/provider.dart';

import 'Backend/songlisttoplay.dart';
import 'Backend/playlisttransfer.dart';
import 'Backend/localmusic.dart';
import 'localmusicpage.dart';
import 'radiomenu.dart';
import 'playlistview.dart';
import 'Backend/playlistsmanager.dart';
import 'Backend/followedartistdb.dart';
import 'Backend/providers/privdersenums.dart';
import 'miniArtistView.dart';
import 'Backend/songdata.dart';
import 'Backend/albumsSaved.dart';
import 'libraryabumView.dart';

class Playlistmenu extends StatefulWidget {
  const Playlistmenu({super.key});

  @override
  State<Playlistmenu> createState() => _PlaylistmenuState();
}

class _PlaylistmenuState extends State<Playlistmenu> {
  List<Map<String, dynamic>> playlists = [];
  List<SimplifiedArtist> artists = [];
  List<Map<String, dynamic>> radios = [];
  List<Albumc> albums = [];

  AppDatabase? _appDb;
  ArtistDatabase? _artistDb;
  AlbumDatabase? _albumDB;

  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    mainAxisExtent: 266,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
  );

  // ─────────────────────────────────────────────────────────────
  // Ciclo de vida
  // ─────────────────────────────────────────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appDb ??= context.read<AppDatabase>();
    _artistDb ??= context.read<ArtistDatabase>();
    _albumDB ??= context.read<AlbumDatabase>();

    _appDb?.removeListener(_onPlaylistsChanged);
    _artistDb?.removeListener(_onArtistsChanged);
    _albumDB?.removeListener(_onAlbumsChanged);

    _appDb?.addListener(_onPlaylistsChanged);
    _artistDb?.addListener(_onArtistsChanged);
    _albumDB?.addListener(_onAlbumsChanged);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _appDb?.removeListener(_onPlaylistsChanged);
    _artistDb?.removeListener(_onArtistsChanged);
    _albumDB?.removeListener(_onAlbumsChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await context.read<AppDatabase>().getPlaylists();
    final r = await context.read<AppDatabase>().getRadios();
    final a = await context.read<ArtistDatabase>().getFollowedArtists();
    final al = await context.read<AlbumDatabase>().getSavedAlbums();
    if (!mounted) return;
    setState(() {
      playlists = p;
      radios = r;
      artists = a;
      albums = al;
    });
  }

  void _onPlaylistsChanged() {
    if (!mounted) return;
    final db = context.read<AppDatabase>();
    setState(() {
      playlists = db.playlists;
      radios = db.radios;
    });
  }

  void _onArtistsChanged() {
    if (!mounted) return;
    setState(() => artists = context.read<ArtistDatabase>().followedartists);
  }

  void _onAlbumsChanged() {
    if (!mounted) return;
    setState(() => albums = context.read<AlbumDatabase>().savedAlbums);
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  bool _importing = false;

  Future<void> _importPlaylists() async {
    if (_importing) return;
    final appDb = context.read<AppDatabase>();
    final songDb = context.read<SongDatabase>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _importing = true);
    try {
      final msg = await PlaylistTransfer.importFromPicker(appDb, songDb);
      if (msg != null) messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      debugPrint('Import falló: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not import that file')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  ArtistInfo _rowToRadioArtist(Map<String, dynamic> row) {
    return ArtistInfo(
      id: row['artist_id'] as String,
      name: row['name'] as String,
      source: metadataprovider.values.firstWhere(
        (e) => e.name == row['source'],
        orElse: () => metadataprovider.values.first,
      ),
      thumbnailUrl: (row['thumbnail'] as String?) ?? '',
      url: '',
    );
  }

  Widget _buildRadioTile(Map<String, dynamic> row) {
    final thumb = (row['thumbnail'] as String?) ?? '';

    Widget placeholder() => Container(
      color: AppColors.bordier,
      alignment: Alignment.center,
      child: Icon(Icons.radio, size: 80, color: AppColors.bordierlight),
    );

    return GestureDetector(
      key: ValueKey('radio_${row["source"]}_${row["artist_id"]}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Radiomenu(artistdata: _rowToRadioArtist(row)),
        ),
      ),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1 / 1,
            child: Container(
              width: 160,
              height: 160,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.bordier,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumb.isEmpty
                      ? placeholder()
                      : Image.network(
                          thumb,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => placeholder(),
                        ),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.radio, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'RADIO',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontFamily: "Adwaita",
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: AlignmentGeometry.topLeft,
            child: Text(
              '${row["name"]} radio',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                color: AppColors.text,
                fontFamily: "Adwaita",
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const Align(
            alignment: AlignmentGeometry.bottomLeft,
            child: Text(
              "Radio",
              style: TextStyle(
                fontSize: 15,
                color: AppColors.text2,
                fontFamily: "Adwaita",
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 22,
                color: AppColors.text,
                fontFamily: "Adwaita",
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _emptyText(String text) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            color: AppColors.text2,
            fontFamily: "Adwaita",
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 20,
        right: 20,
        top: kToolbarHeight + 8,
      ),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: LocalMusicManager.instance,
              builder: (context, _) {
                final lm = LocalMusicManager.instance;
                if (!lm.enabled) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color: AppColors.bordier,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LocalMusicPage(),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.phone_android_rounded,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'On this device',
                                    style: TextStyle(
                                      fontSize: 17,
                                      color: AppColors.text,
                                      fontFamily: 'Adwaita',
                                      fontWeight: FontWeight.w700,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  Text(
                                    '${lm.songs.length} songs',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.text2,
                                      fontFamily: 'Adwaita',
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: AppColors.text2),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ─── Sección 1: Playlists ───
          SliverToBoxAdapter(
            child: _sectionTitle(
              "Your Playlists",
              trailing: _importing
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    )
                  : IconButton(
                      onPressed: _importPlaylists,
                      tooltip: 'Import playlist',
                      icon: Icon(
                        Icons.file_download_outlined,
                        color: AppColors.text2,
                      ),
                    ),
            ),
          ),
          SliverGrid(
            gridDelegate: _gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == 0) return _buildCreatePlaylistButton(context);
                if (index == 1) return _buildFavoritesTile();

                final i = index - 2;
                if (i < playlists.length) {
                  final data = playlists[i];
                  return Playlistview(
                    key: ValueKey('playlist_${data["id"]}'),
                    data: data,
                  );
                }
                return _buildRadioTile(radios[i - playlists.length]);
              },
              childCount: playlists.length + radios.length + 2,
              findChildIndexCallback: (key) {
                if (key is! ValueKey<String>) return null;
                final v = key.value;

                final pi = playlists.indexWhere(
                  (p) => 'playlist_${p["id"]}' == v,
                );
                if (pi != -1) return pi + 2; // +2 por "Create" y "Favorites"

                final ri = radios.indexWhere(
                  (r) => 'radio_${r["source"]}_${r["artist_id"]}' == v,
                );
                if (ri != -1) return playlists.length + 2 + ri;

                return null;
              },
            ),
          ),

          // ─── Sección 2: Artistas seguidos ───
          SliverToBoxAdapter(child: _sectionTitle("Followed Artists")),
          if (artists.isEmpty)
            _emptyText("You don't follow any artists yet.")
          else
            SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 266,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => Miniartistview(data: artists[index]),
                childCount: artists.length,
              ),
            ),

          // ─── Sección 3: Álbumes guardados ───
          SliverToBoxAdapter(child: _sectionTitle("Saved Albums")),
          if (albums.isEmpty)
            _emptyText("You haven't saved any album yet.")
          else
            SliverGrid(
              gridDelegate: _gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, index) => AlbumView(data: albums[index], label: ""),
                childCount: albums.length,
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Tile de favoritos
  // ─────────────────────────────────────────────────────────────

  Widget _buildFavoritesTile() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const Playlistlist(
            playlist: AppDatabase.favoritesId,
            name: "Favorites",
          ),
        ),
      ),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1 / 1,
            child: Container(
              width: 160,
              height: 160,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.bordier,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Align(
                alignment: AlignmentGeometry.center,
                child: Icon(
                  Icons.favorite,
                  size: 140,
                  color: AppColors.bordierlight,
                ),
              ),
            ),
          ),
          Text(
            "Favorites",
            style: const TextStyle(
              fontSize: 20,
              color: AppColors.text,
              fontFamily: "Adwaita",
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Botón "Create Playlist"
  // ─────────────────────────────────────────────────────────────

  Widget _buildCreatePlaylistButton(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) {
          bool enabled = false;
          String playlistName = "";

          return StatefulBuilder(
            builder: (context, setLocalState) {
              return AlertDialog(
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                elevation: 16,
                shadowColor: Colors.black.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: Colors.white.withOpacity(0.06),
                    width: 1,
                  ),
                ),
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),

                // ── Header: icon badge + título + subtítulo ────────────────────
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.accent.withOpacity(0.22),
                            AppColors.accent.withOpacity(0.06),
                          ],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.accent.withOpacity(0.30),
                        ),
                      ),
                      child: Icon(
                        Icons.playlist_add_rounded,
                        color: AppColors.accent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Create Playlist",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        color: AppColors.text,
                        fontFamily: "Adwaita",
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Give your new playlist a name",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.text.withOpacity(0.55),
                        fontFamily: "Adwaita",
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),

                // ── Cuerpo: label + field + counter ────────────────────────────
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "PLAYLIST NAME",
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.4,
                        color: AppColors.text2,
                        fontFamily: "Adwaita",
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 8),

                    TextField(
                      autofocus: true,
                      onChanged: (v) => setLocalState(() {
                        playlistName = v;
                        enabled = v.trim().isNotEmpty;
                      }),
                      maxLength: 25,
                      cursorColor: AppColors.accent,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontFamily: "Adwaita",
                        fontSize: 15,
                      ),
                      buildCounter: (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                      decoration: InputDecoration(
                        hintText: 'e.g. Late night drive',
                        hintStyle: TextStyle(
                          color: AppColors.text2disabled,
                          fontFamily: "Adwaita",
                          fontSize: 15,
                        ),
                        filled: true,
                        fillColor: AppColors.bordier.withOpacity(0.60),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.bordier),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: AppColors.accent,
                            width: 1.5,
                          ),
                        ),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 12, right: 8),
                          child: Icon(
                            Icons.edit_rounded,
                            size: 18,
                            color: AppColors.text2disabled,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Contador custom, con cambio de color progresivo
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${playlistName.length}/25',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Adwaita',
                          fontWeight: FontWeight.w600,
                          color: playlistName.length >= 25
                              ? Colors.red.shade400
                              : playlistName.length >= 20
                              ? AppColors.accent
                              : AppColors.text2disabled,
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Acciones ──────────────────────────────────────────────────
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, 'Cancel'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.text.withOpacity(0.70),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Adwaita',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: enabled
                        ? () async {
                            final appDb = dialogContext.read<AppDatabase>();
                            Navigator.pop(dialogContext, 'OK');
                            await appDb.createPlaylist(playlistName);
                          }
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.background,
                      disabledBackgroundColor: AppColors.bordier.withOpacity(
                        0.6,
                      ),
                      disabledForegroundColor: AppColors.text2disabled,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Adwaita',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    child: const Text('Create'),
                  ),
                ],
              );
            },
          );
        },
      ),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1 / 1,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.bordier,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Align(
                alignment: Alignment.center,
                child: Icon(
                  Icons.add,
                  size: 140,
                  color: AppColors.bordierlight,
                ),
              ),
            ),
          ),
          const Text(
            "Create Playlist",
            style: TextStyle(
              fontSize: 20,
              color: AppColors.text,
              fontFamily: "Adwaita",
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
