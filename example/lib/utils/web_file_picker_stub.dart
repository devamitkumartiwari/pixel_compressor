import 'web_file_picker.dart';

/// Only available on the web; native platforms use the gallery picker.
Future<List<WebPickedFile>> pickWebFiles({
  required String accept,
  bool multiple = false,
}) => throw UnsupportedError('pickWebFiles is only available on the web');
