import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the share sheet with [bytes] as [fileName].
Future<void> saveFile(Uint8List bytes, String fileName, String mimeType) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
      fileNameOverrides: [fileName],
    ),
  );
}
