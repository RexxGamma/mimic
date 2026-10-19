import 'package:flutter/material.dart';

import 'appcolors.dart';
import 'artist.dart';

import 'dart:io';

class Miniartistview extends StatelessWidget {
  const Miniartistview({super.key, required this.data});
  final data;

  @override
  Widget build(BuildContext context) {
    debugPrint("MINIARTIST RECIBE: ${data.downloadBannerPath}");
    ImageProvider banner() {
      if (data.downloadBannerPath != null) {
        print("OK");
        return FileImage(File(data.downloadBannerPath!));
      } else {
        print("OKN'T");
        return NetworkImage(data?.thumbnailUrl ?? "");
      }
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ArtistWidet(id: data.id)),
          );
        },
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: AspectRatio(
                aspectRatio: 1,
                child: CircleAvatar(
                  radius: double.infinity,
                  backgroundImage: banner(),
                ),
              ),
            ),

            SizedBox(height: 21),

            Text(
              data.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                color: AppColors.text,
                fontFamily: "Adwaita",
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

