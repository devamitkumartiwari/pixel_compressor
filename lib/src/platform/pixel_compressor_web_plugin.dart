import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import '../image/image_compress_platform.dart';
import '../image/web/image_compress_web.dart';

/// Web registration. Only image compression is available on the web; the
/// video API has no web implementation.
class PixelCompressorWebPlugin() {
  static void registerWith(Registrar registrar) {
    PixelImageCompressPlatform.instance = PixelImageCompressWeb();
  }
}
