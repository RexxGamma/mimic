import 'package:flutter/material.dart';

import 'appcolors.dart';
import 'Backend/songdata.dart';
import 'Backend/songlisttoplay.dart';

import 'package:provider/provider.dart';

class Miniplaylistview extends StatefulWidget {
  const new({super.key, required this.data, required this.songdata});
  final data;
  final songdata;

  @override
  State<Miniplaylistview> createState() => _MiniplaylistviewState();
}

class _MiniplaylistviewState extends State<Miniplaylistview> {
  var songsnumber;
  var playlisttime;

  List<SongInfo> songlist = [];

  @override
  void initState() {
    super.initState();
    getTracks();
  }

  void getTracks() async {
    var s = await context.read<SongDatabase>().getTracks(widget.data["id"]);

    print("SOS SOS SOS: $s");
    setState(() {
      songlist = s;
      PlaylistManager.instance.playlistChanged();
      print("PLAYLIST ${widget.data["id"]} → ${songlist.length} canciones");
    });
  }

  @override
  Widget build(BuildContext context) {
    print("DATASJKDASDKSLKDALKKLSD  ${widget.data["id"]}");
    return GestureDetector(
      onTap: () {
        context.read<SongDatabase>().addTracks(
          widget.songdata,
          widget.data["id"],
        );
        Navigator.of(context).pop();
      },
      child: Column(
        children: [
          //Banner
          Container(
            width: 140,
            height: 140,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(5)),
            child: playlistBanner(songlist),
          ),

          //Title
          Align(
            alignment: AlignmentGeometry.topLeft,
            child: Text(
              widget.data["title"],
              maxLines: 2,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.text,
                fontFamily: "Adwaita",
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          ),

          //Playlist Number of songs
          Align(
            alignment: AlignmentGeometry.bottomLeft,
            child: Text(
              "${songlist.length} Songs",
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
}

Widget playlistBanner(List<SongInfo> songs) {
  final tracks = songs.take(4).toList();

  if (tracks.isEmpty) {
    return Container(
      color: AppColors.bordier,
      child: Icon(Icons.music_note, size: 100, color: AppColors.bordierlight),
    );
  }

  if (tracks.length == 1) {
    return Image.network(tracks[0].thumbnails[3].url, fit: BoxFit.cover);
  }

  return GridView.builder(
    physics: const NeverScrollableScrollPhysics(),
    padding: EdgeInsets.zero,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
    ),
    itemCount: tracks.length,
    itemBuilder: (context, index) {
      return Image.network(tracks[index].thumbnails[3].url, fit: BoxFit.cover);
    },
  );
}

class PlaylistManager extends ChangeNotifier {
  static final PlaylistManager instance = PlaylistManager._internal();

  PlaylistManager._internal();

  void playlistChanged() {
    notifyListeners();
  }
}
