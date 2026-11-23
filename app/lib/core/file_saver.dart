import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_saver/save_file_io.dart'
    if (dart.library.js_interop) 'file_saver/save_file_web.dart'
    as platform;

/// Hands a generated file to the user: a browser download on the web, the
/// share sheet on Android (to save it to Files, Drive, email it...).
typedef FileSaver =
    Future<void> Function(Uint8List bytes, String fileName, String mimeType);

final fileSaverProvider = Provider<FileSaver>((ref) => platform.saveFile);
