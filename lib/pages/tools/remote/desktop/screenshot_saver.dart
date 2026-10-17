import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../../../components/share.dart';

Future<void> copyScreenshotToClipboard(Uint8List png) =>
    Pasteboard.writeImage(png);

Future<String?> saveBytesAs(
  Uint8List bytes, {
  required String dialogTitle,
  required String fileName,
}) async {
  final savedPath = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: bytes,
  );
  if (savedPath == null || savedPath.isEmpty) return null;
  if (io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS) {
    await io.File(savedPath).writeAsBytes(bytes, flush: true);
  }
  return savedPath;
}

/// Copies the GIF file at [filePath] to the system clipboard as a file
/// reference (paste-as-file on desktop, no-op on mobile).
Future<void> copyGifFileToClipboard(String filePath) =>
    copyFileToClipboard(filePath);
