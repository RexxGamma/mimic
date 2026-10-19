import 'package:flutter/material.dart';
import 'package:mimic/Backend/songdata.dart';
import 'appcolors.dart';
import 'artist.dart';

class Artistlinks extends StatelessWidget {
  const new({super.key, required this.data});
  final SongInfo data;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.3,
        maxChildSize: 1,
        builder: (context, ScrollController) {
          return Container(
          height: 800,
          decoration: BoxDecoration(

          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
                    
            ),

            child: ListView.builder(
              controller: ScrollController,
              itemCount: data.artists.length,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                
                return //See Artist 
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ArtistWidet(id: data.artists[index].id,),
                    ),
                  );
                }, 
                child: Material(
                  color: AppColors.background,
                  child: ListTile(
                    //Icon
                    leading: Stack(
                      children: [
                        Icon(
                          Icons.person,
                          size: 35,
                          color: AppColors.text,
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.music_note,
                              size: 20,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  
                      //Text
                      title: Text( "View Artist", style: TextStyle(color: AppColors.text,fontWeight: FontWeight.w600, ),),

                      //Artist
                      subtitle: Text( data.artists[index].name, style: TextStyle(color: AppColors.text2),),
                  ),
                ),
              );
              }
              
            ),
          );
        });
  }
}