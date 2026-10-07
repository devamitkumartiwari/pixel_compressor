import 'package:flutter/foundation.dart';

export 'web_file_picker_stub.dart'
    if (dart.library.js_interop) 'web_file_picker_web.dart';

/// A file the user picked in the browser.
typedef WebPickedFile = ({String name, Uint8List bytes});
