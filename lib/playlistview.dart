import 'package:flutter/material.dart';
import 'package:mimic/playlistlist.dart';

import 'appcolors.dart';
import 'Backend/songdata.dart';
import 'Backend/songlisttoplay.dart';

import 'package:provider/provider.dart';

class Playlistview extends StatefulWidget {
  Playlistview({super.key, required this.data});
  final data;

  @override
  State<Playlistview> createState() => _PlaylistviewState();
}

class _PlaylistviewState extends State<Playlistview> {
  List<SongInfo> songlist = [];
  SongDatabase? _songDb;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _songDb ??= context.read<SongDatabase>();
    if (_songDb != null) {
      _songDb!.removeListener(_onSongsChanged);
      _songDb!.addListener(_onSongsChanged);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant Playlistview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data["id"] != widget.data["id"]) {
      setState(
        () => songlist = [],
      ); // evita mostrar las canciones de la anterior
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.data["id"];
    final s = await context.read<SongDatabase>().getTracks(id);
    if (!mounted || id != widget.data["id"]) return; // llegó tarde, se descarta
    setState(() => songlist = s);
  }

  void _onSongsChanged() => _load();

  @override
  void dispose() {
    _songDb?.removeListener(_onSongsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Playlistlist(
              playlist: widget.data["id"],
              name: widget.data["title"],
            ),
          ),
        );
      },
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1 / 1,
            child: Container(
              width: 160,
              height: 160,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(5)),
              child: playlistBanner(
                songlist,
                (widget.data["cover"] ?? '') as String,
              ),
            ),
          ),
          Align(
            alignment: AlignmentGeometry.topLeft,
            child: Text(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,

              widget.data["title"],
              style: TextStyle(
                fontSize: 14,
                color: AppColors.text,
                fontFamily: "Adwaita",
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Align(
            alignment: AlignmentGeometry.bottomLeft,
            child: Text(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              "${songlist.length} Songs",
              style: TextStyle(
                fontSize: 12,
                color: AppColors.text2,
                fontFamily: "Adwaita",
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
