import 'package:flutter/material.dart';
import "appcolors.dart";
import 'package:intl/intl.dart';

Future showDetailsPopup(BuildContext context, data) {
  final fmt = DateFormat('d MMM yyyy');
  print("LOLLOOODOSDOSODS $data");
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true, 
    backgroundColor: AppColors.background,
    useSafeArea: true,
    builder: (ctx) {
      

      return DraggableScrollableSheet(
       
        initialChildSize: 0.55,
        minChildSize: 0.30,    
        maxChildSize: 0.95,   
        expand: false,          
        snap: true,            
        snapSizes: const [0.55, 0.95],
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                Text(
                  "Artist",
                  style: TextStyle(
                    color: AppColors.text,
                    fontFamily: "Adwaita",
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),


                Text(
                  data.artists.first.name,
                  style: TextStyle(
                    color: AppColors.text2,
                    fontFamily: "Adwaita",
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),


                SizedBox(height: 20,),

                Text(
                  "Album",
                  style: TextStyle(
                    color: AppColors.text,
                    fontFamily: "Adwaita",
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),


                Text(
                  data.album['title'] ?? "Unknown Album",
                  style: TextStyle(
                    color: AppColors.text2,
                    fontFamily: "Adwaita",
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),


                SizedBox(height: 20,),


                Text(
                  "Song id",
                  style: TextStyle(
                    color: AppColors.text,
                    fontFamily: "Adwaita",
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),


                Text(
                  data.id,
                  style: TextStyle(
                    color: AppColors.text2,
                    fontFamily: "Adwaita",
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),



                SizedBox(height: 20,),


                Text(
                  "Release Date",
                  style: TextStyle(
                    color: AppColors.text,
                    fontFamily: "Adwaita",
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),


                Text(
                  data.releaseDate != null ? fmt.format(data.releaseDate!)  : '—',
                  style: TextStyle(
                    color: AppColors.text2,
                    fontFamily: "Adwaita",
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),



                SizedBox(height: 20,),


                Text(
                  "Bpm",
                  style: TextStyle(
                    color: AppColors.text,
                    fontFamily: "Adwaita",
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),


                Text(
                  data.bpm.toString(),
                  style: TextStyle(
                    color: AppColors.text2,
                    fontFamily: "Adwaita",
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),



                SizedBox(height: 20,),


                Text(
                  "Isrc",
                  style: TextStyle(
                    color: AppColors.text,
                    fontFamily: "Adwaita",
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),


                Text(
                  data.isrc ?? "-",
                  style: TextStyle(
                    color: AppColors.text2,
                    fontFamily: "Adwaita",
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),


                SizedBox(height: 20,),


                Text(
                  "Genre",
                  style: TextStyle(
                    color: AppColors.text,
                    fontFamily: "Adwaita",
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),


                Text(
                  data.genre ?? "--",
                  style: TextStyle(
                    color: AppColors.text2,
                    fontFamily: "Adwaita",
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),

              ]
            ),
          );
        }
      );
    }
  );
}