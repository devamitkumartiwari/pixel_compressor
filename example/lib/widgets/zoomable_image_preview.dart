import 'dart:io';

import 'package:flutter/material.dart';

/// A thumbnail that opens a pinch-to-zoom full-screen viewer on tap.
class ZoomableImagePreview extends StatelessWidget {
  const ZoomableImagePreview({
    super.key,
    required this.file,
    this.height = 180,
  });

  final File file;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _FullScreenImage(file: file),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          file,
          height: height,
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      ),
    );
  }
}

class _FullScreenImage extends StatelessWidget {
  const _FullScreenImage({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: Image.file(file),
        ),
      ),
    );
  }
}
