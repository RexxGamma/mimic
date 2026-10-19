import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'Backend/providers/providermanager.dart';
import 'appcolors.dart';
import 'Backend/providers/streaming/streamingmanager.dart';
import 'searchmenu.dart';
import 'Backend/providers/privdersenums.dart';

Future<metadataprovider?> showProviderSheet(BuildContext context) {
  final currentProvider = StreamingManager.instance.provider;

  return showModalBottomSheet<metadataprovider>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    useSafeArea: true,
    builder: (ctx) {
      final mp = ctx.watch<MetadataProvider>();

      return DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.30,
        maxChildSize: 0.95,
        expand: false,
        snap: true,
        snapSizes: const [0.55, 0.95],
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              // ─────────────── Metadata Source ───────────────
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Text(
                    'Metadata Source',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ),
              for (final type in metadataprovider.selectable)
                RadioListTile<metadataprovider>(
                  value: type,
                  groupValue: mp.type,
                  fillColor: WidgetStatePropertyAll(AppColors.accent),
                  title: Text(
                    _labelFor(type),
                    style: const TextStyle(color: AppColors.text),
                  ),
                  subtitle: Text(
                    _subtitleFor(type),
                    style: const TextStyle(color: AppColors.text),
                  ),
                  onChanged: (v) => Navigator.of(ctx).pop(v),
                ),

              const SizedBox(height: 8),
              Divider(height: 1, color: AppColors.bordierlight),

              // ─────────────── Streaming Source ──────────────
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Text(
                    'Streaming Source',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ),
              for (final type in StreamingProvider.selectable)
                RadioListTile<StreamingProvider>(
                  value: type,
                  groupValue: currentProvider,
                  fillColor: WidgetStatePropertyAll(AppColors.accent),

                  title: Text(
                    _labelForStreaiming(type),
                    style: const TextStyle(color: AppColors.text),
                  ),
                  onChanged: (v) {
                    if (v == null) return;
                    resultses = null;
                    artistlist = null;
                    albumlist = null;
                    updatesong = null;
                    StreamingManager.instance.configure(provider: v);
                    print("QUESO LOL ${StreamingManager.instance.provider}");
                    Navigator.of(ctx).pop(); // o el método que uses
                    // No cerramos el sheet
                  },
                ),
              const SizedBox(height: 8),
            ],
          );
        },
      );
    },
  );
}

String _labelFor(metadataprovider t) {
  switch (t) {
    case metadataprovider.deezer:
      return 'Deezer';
    case metadataprovider.soundcloud:
      return 'SoundCloud';
    case metadataprovider.itunes:
      return "iTunes";
    case metadataprovider.musicbrainz:
      return "MusicBrainz";
    case metadataprovider.local:
      return "";
  }
}

String _subtitleFor(metadataprovider t) {
  switch (t) {
    case metadataprovider.deezer:
      return 'Complete catalog';
    case metadataprovider.soundcloud:
      return 'Remixes, bootlegs and indie artist';
    case metadataprovider.itunes:
      return "fastests metadata provider";
    case metadataprovider.musicbrainz:
      return "Biggest catalog,some tracks don't have banner";
    case metadataprovider.local:
      return "";
  }
}

String _labelForStreaiming(StreamingProvider t) {
  switch (t) {
    case StreamingProvider.youtube:
      return 'YouTube';
    case StreamingProvider.soundcloud:
      return 'SoundCloud';
    case StreamingProvider.local:
      return "";
  }
}
