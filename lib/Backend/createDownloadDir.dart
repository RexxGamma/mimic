import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Directory> getDownloadDirectory() async {
  final appDir = await getApplicationDocumentsDirectory();

  final downloadDir = Directory(
    p.join(appDir.path, 'Downloads'),
  );

  if (!await downloadDir.exists()) {
    await downloadDir.create(recursive: true);
  }

  return downloadDir;
}