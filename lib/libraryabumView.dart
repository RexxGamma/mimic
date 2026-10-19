import 'package:flutter/material.dart';
import 'package:mimic/albumsonglist.dart';

import 'appcolors.dart';

import 'dart:io';

class AlbumView extends StatefulWidget {
  final data;
  final label;
  const AlbumView({super.key, required this.data, required this.label});

  @override
  State<AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<AlbumView> {
  @override
  Widget build(BuildContext context) {
    Widget banner() {
      if (widget.data.downloadBannerPath != null) {
        return Container(
          color: AppColors.bordier,
          child: Image.file(
            File(widget.data.downloadBannerPath!),
            cacheWidth: 800,
            gaplessPlayback: true,
            fit: BoxFit.cover,
          ),
        );
      }

      return Container(
        color: AppColors.bordier,
        child: Image.network(
          widget.data.bannerurl,
          cacheWidth: 800,
          gaplessPlayback: true,
          fit: BoxFit.cover,

          errorBuilder: (_, __, ___) => Container(
            color: AppColors.bordier,
            child: const Icon(
              Icons.music_note,
              size: 100,
              color: AppColors.text2,
            ),
          ),
        ),
      );
    }

    debugPrint("Album DATA: ${widget.data}");
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Albumsonglist(
              albid: widget.data.id,
              albumdata: widget.data,
              type: widget.label,
            ),
          ),
        );
      },
      child: SizedBox(
        width: 160,
        height: 300,
        child: Column(
          children: [
            //Banner
            AspectRatio(
              aspectRatio: 1 / 1,
              child: Container(
                width: 160,
                height: 170,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                ),
                child: banner(),
              ),
            ),

            //Title
            Align(
              alignment: AlignmentGeometry.topLeft,
              child: Text(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,

                widget.data.name ?? "",
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

            //Album date release and album type
            Align(
              alignment: AlignmentGeometry.centerStart,
              child: Text(
                "${widget.data.year ?? ""} ${widget.label}",
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.text2,
                  fontFamily: "Adwaita",
                  fontWeight: FontWeight.w400,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
