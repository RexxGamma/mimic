import 'package:flutter/material.dart';
import 'package:mimic/appcolors.dart';

import 'track.dart';
import 'Backend/providers/providermanager.dart';
import 'miniArtistView.dart';
import 'libraryabumView.dart';
import 'Backend/recordtypelabels.dart';
import 'Backend/searchHistory.dart';

import 'package:provider/provider.dart';

import 'Backend/providers/privdersenums.dart';

// Globales: se mantienen a propósito para que los resultados, la consulta y la
// pestaña elegida sobrevivan si el State se destruye al cambiar de sección.
var resultses;
var updatesong;
var artistlist;
var albumlist;
var provider;
String lastQuery = '';
Set<SearchType> lastSearchMode = {SearchType.songz};

class Searchmenu extends StatefulWidget {
  final onsearch;
  Searchmenu({super.key, required this.onsearch});

  @override
  State<Searchmenu> createState() => _SearchmenuState();
}

class _SearchmenuState extends State<Searchmenu> {
  metadataprovider? _lastType;

  late Set<SearchType> selectedSearchMode = {...lastSearchMode};

  final TextEditingController _controller = TextEditingController(
    text: lastQuery,
  );
  final FocusNode _focus = FocusNode();

  List<String> _history = [];
  bool _loading = false;
  bool _failed = false;
  int _searchId = 0; // para descartar respuestas viejas

  // ───────────────────────── Ciclo de vida ─────────────────────────

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    _focus.addListener(_refresh);
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _focus.removeListener(_refresh);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get _hasResults =>
      resultses != null || artistlist != null || albumlist != null;

  // ───────────────────────── Historial ─────────────────────────

  Future<void> _loadHistory() async {
    final h = await SearchHistory.load();
    if (!mounted) return;
    setState(() => _history = h);
  }

  void _deleteFromHistory(String query) {
    setState(() => _history = SearchHistory.without(_history, query));
    SearchHistory.save(_history);
  }

  Future<void> _confirmClearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(
          'Clear search history',
          style: TextStyle(
            color: AppColors.text,
            fontFamily: 'Adwaita',
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Remove all ${_history.length} recent searches?',
          style: TextStyle(color: AppColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    setState(() => _history = []);
    SearchHistory.save(_history);
  }

  // ───────────────────────── Búsqueda ─────────────────────────

  Future<void> _submit(String value) async {
    final q = value.trim();
    if (q.isEmpty) return;

    _controller.text = q;
    _focus.unfocus();
    widget.onsearch();

    // Primero en memoria (UI inmediata), luego a disco
    setState(() => _history = SearchHistory.withQuery(_history, q));
    SearchHistory.save(_history);

    await _searchAll(q);
  }

  Future<void> _searchAll(String query) async {
    final mp = context.read<MetadataProvider>();
    final id = ++_searchId;
    lastQuery = query;

    setState(() {
      _loading = true;
      _failed = false;
    });

    // Si una de las 3 peticiones falla, las otras igual se muestran
    Future<T?> safe<T>(Future<T> f) =>
        f.then<T?>((v) => v).catchError((Object e) {
          debugPrint('Search error: $e');
          return null;
        });

    final (songs, artists, albums) = await (
      safe(mp.searchAll(query)),
      safe(mp.searchArtists(query)),
      safe(mp.searchAlbums(query)),
    ).wait;

    // Llegó tarde: hubo otra búsqueda, o se cambió de proveedor
    if (!mounted || id != _searchId) return;

    final allFailed = songs == null && artists == null && albums == null;

    setState(() {
      _loading = false;
      _failed = allFailed;
      if (!allFailed) {
        provider = mp.type;
        resultses = songs;
        artistlist = artists;
        albumlist = albums;
      }
    });
  }

  void _clearField() {
    _controller.clear();
    _focus.requestFocus();
  }

  // ───────────────────────── UI ─────────────────────────

  Widget _hint(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: AppColors.bordierlight),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.text2,
                fontFamily: "Adwaita",
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyPanel(String text) {
    final q = text.toLowerCase();
    final typing = q.isNotEmpty;

    final items = typing
        ? _history.where((h) => h.toLowerCase().contains(q)).toList()
        : _history;

    if (items.isEmpty) {
      return typing
          ? _hint(Icons.search, 'Press search to look for "$text"')
          : _hint(Icons.search, 'Search for songs, albums or artists');
    }

    // TextFieldTapRegion: tocar aquí no cuenta como "tocar fuera" del campo,
    // así que el campo no pierde el foco antes de que el toque llegue al item.
    return TextFieldTapRegion(
      child: Material(
        color: AppColors.background,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(top: 8, bottom: 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      typing ? 'Suggestions' : 'Recent searches',
                      style: const TextStyle(
                        fontSize: 18,
                        color: AppColors.text,
                        fontFamily: "Adwaita",
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (!typing)
                    TextButton(
                      onPressed: _confirmClearHistory,
                      child: Text(
                        'Clear all',
                        style: TextStyle(color: AppColors.text2),
                      ),
                    ),
                ],
              ),
            ),
            for (final item in items)
              ListTile(
                leading: Icon(Icons.history, color: AppColors.text2),
                title: Text(
                  item,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontFamily: "Adwaita",
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.close, size: 20, color: AppColors.text2),
                  onPressed: () => _deleteFromHistory(item),
                ),
                onTap: () => _submit(item),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mp = context.watch<MetadataProvider>();

    if (_lastType != null && _lastType != mp.type) {
      _lastType = mp.type;
      _searchId++; // descarta cualquier búsqueda en curso del proveedor anterior
      _loading = false;
      _failed = false;
      resultses = null;
      artistlist = null;
      albumlist = null;
    } else if (_lastType == null) {
      _lastType = mp.type;
    }

    final text = _controller.text.trim();

    // Mientras escribes algo distinto a la última búsqueda (o borras el campo)
    // se ve el historial. Si no hay resultados todavía, también.
    final editing = _focus.hasFocus && text != lastQuery;
    final showHistory = editing || (!_hasResults && !_loading && !_failed);

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: SizedBox(
                height: 50,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submit,
                  onTapOutside: (_) => _focus.unfocus(),
                  cursorColor: AppColors.accent,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontFamily: 'Adwaita',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search songs, albums, artists…',
                    hintStyle: TextStyle(
                      color: AppColors.text2disabled,
                      fontFamily: 'Adwaita',
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        child: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: _focus.hasFocus
                              ? AppColors.accent
                              : AppColors.text2,
                        ),
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: AppColors.text2,
                              ),
                              splashRadius: 20,
                              onPressed: _clearField,
                            ),
                          ),
                    filled: true,
                    fillColor: AppColors.bordier.withOpacity(0.6),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 15,
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: showHistory
                  ? _historyPanel(text)
                  : searchresults(
                      selectedSearchMode,
                      (Set<SearchType> newSelection) {
                        setState(() {
                          selectedSearchMode = newSelection;
                          lastSearchMode = {...newSelection};
                        });
                      },
                      loading: _loading,
                      failed: _failed,
                      onRetry: () => _searchAll(lastQuery),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Segmented button view type
enum SearchType { artizt, albumz, songz }

Widget _centerMessage(String text) {
  return Center(
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        color: AppColors.text2,
        fontFamily: "Adwaita",
        decoration: TextDecoration.none,
      ),
    ),
  );
}

Widget searchresults(
  Set<SearchType> searchmode,
  void Function(Set<SearchType>) updateSearchMode, {
  bool loading = false,
  bool failed = false,
  VoidCallback? onRetry,
}) {
  final mode = searchmode.isEmpty ? SearchType.songz : searchmode.first;

  Widget content;

  if (loading) {
    content = Center(
      child: CircularProgressIndicator(
        backgroundColor: AppColors.bordier,
        color: AppColors.accent,
      ),
    );
  } else if (failed) {
    content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _centerMessage("Couldn't complete the search"),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text("Retry", style: TextStyle(color: AppColors.text)),
          ),
        ],
      ),
    );
  } else {
    switch (mode) {
      case SearchType.songz:
        content = (resultses == null || resultses.isEmpty)
            ? _centerMessage("No songs found")
            : Padding(
                padding: const EdgeInsets.only(left: 10, right: 10),
                child: ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: resultses.length,
                  itemBuilder: (context, index) =>
                      Onesong(song: resultses[index]),
                ),
              );
        break;

      case SearchType.artizt:
        content = (artistlist == null || artistlist.isEmpty)
            ? _centerMessage("No artists found")
            : GridView.builder(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1 / 1.331,
                  mainAxisSpacing: 3,
                ),
                itemCount: artistlist.length,
                itemBuilder: (context, index) =>
                    Miniartistview(data: artistlist[index]),
              );
        break;

      case SearchType.albumz:
        content = (albumlist == null || albumlist.isEmpty)
            ? _centerMessage("No albums found")
            : Padding(
                padding: const EdgeInsets.all(10),
                child: GridView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1 / 1.277,
                    mainAxisSpacing: 25,
                  ),
                  itemCount: albumlist.length,
                  itemBuilder: (context, index) {
                    final album = albumlist[index];
                    return AlbumView(
                      data: album,
                      label: recordTypeLabel(album.recordType),
                    );
                  },
                ),
              );
        break;
    }
  }

  return Column(
    children: [
      Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 10),
            child: SizedBox(
              height: 45,
              width: 150,
              child: SegmentedButton<SearchType>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  backgroundColor: AppColors.bordier,
                  foregroundColor: AppColors.accent,
                  selectedForegroundColor: AppColors.accentTeammate,
                  selectedBackgroundColor: AppColors.accent,
                  overlayColor: AppColors.surface,
                ),
                segments: const [
                  ButtonSegment(
                    value: SearchType.songz,
                    icon: Icon(Icons.music_note),
                  ),
                  ButtonSegment(
                    value: SearchType.albumz,
                    icon: Icon(Icons.album),
                  ),
                  ButtonSegment(
                    value: SearchType.artizt,
                    icon: Icon(Icons.person),
                  ),
                ],
                selected: searchmode,
                onSelectionChanged: updateSearchMode,
              ),
            ),
          ),
        ],
      ),
      Expanded(child: content),
    ],
  );
}
