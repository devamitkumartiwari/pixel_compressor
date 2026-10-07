import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_file_picker.dart';

/// Opens the browser's file dialog and reads the chosen files. Returns an
/// empty list when the user cancels.
Future<List<WebPickedFile>> pickWebFiles({
  required String accept,
  bool multiple = false,
}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept
    ..multiple = multiple;
  final chosen = Completer<List<web.File>>();
  input.onchange = (web.Event _) {
    final files = input.files;
    chosen.complete([
      for (var i = 0; i < (files?.length ?? 0); i++) files!.item(i)!,
    ]);
  }.toJS;
  input.oncancel = (web.Event _) {
    if (!chosen.isCompleted) chosen.complete(const []);
  }.toJS;
  input.click();

  return [
    for (final file in await chosen.future)
      (
        name: file.name,
        bytes: (await file.arrayBuffer().toDart).toDart.asUint8List(),
      ),
  ];
}
