import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Rounded image preview over a subtle checkerboard (so transparency shows);
/// tap opens a pinch-to-zoom viewer. Formats Flutter can't decode (HEIC on
/// some platforms) fall back to a placeholder.
class const ImagePreview({
  super.key,
  required this.bytes,
  this.height = 200,
  this.label,
  this.fit = .contain,
}) extends StatelessWidget {
  final Uint8List bytes;
  final double height;
  final String? label;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label == null ? 'Image preview' : '$label preview',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _FullScreenImage(bytes: bytes, title: label),
          ),
        ),
        child: ClipRRect(
          borderRadius: .circular(16),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              fit: .expand,
              children: [
                CustomPaint(
                  painter: _CheckerPainter(
                    scheme.surfaceContainerHigh,
                    scheme.surfaceContainerHighest,
                  ),
                ),
                Image.memory(
                  bytes,
                  fit: fit,
                  gaplessPlayback: true,
                  errorBuilder: (context, _, _) => const _NoPreview(),
                ),
                if (label != null)
                  Positioned(left: 8, top: 8, child: _Tag(label!)),
                const Positioned(
                  right: 8,
                  bottom: 8,
                  child: _Tag('', icon: Icons.zoom_out_map_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Before and after previews side by side.
class const BeforeAfter({
  super.key,
  required this.before,
  required this.after,
  this.height = 180,
}) extends StatelessWidget {
  final Uint8List before;
  final Uint8List after;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ImagePreview(bytes: before, label: 'Before', height: height),
        ),
        const SizedBox(width: Insets.sm),
        Expanded(
          child: ImagePreview(bytes: after, label: 'After', height: height),
        ),
      ],
    );
  }
}

class const _Tag(this.text, {this.icon}) extends StatelessWidget {
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: .symmetric(horizontal: icon == null ? 8 : 5, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: .circular(999),
      ),
      child: icon != null
          ? Icon(icon, size: 14, color: Colors.white)
          : Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: .w700,
              ),
            ),
    );
  }
}

class const _NoPreview() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: .min,
        children: [
          Icon(Icons.image_not_supported_outlined, color: color),
          const SizedBox(height: 6),
          Text(
            'No preview for this format',
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CheckerPainter(this.a, this.b) extends CustomPainter {
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    canvas.drawRect(Offset.zero & size, Paint()..color = a);
    final paint = Paint()..color = b;
    for (var y = 0.0; y < size.height; y += cell) {
      for (
        var x = ((y / cell).floor().isEven ? 0.0 : cell);
        x < size.width;
        x += cell * 2
      ) {
        canvas.drawRect(.fromLTWH(x, y, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => old.a != a || old.b != b;
}

class const _FullScreenImage({required this.bytes, this.title})
    extends StatelessWidget {
  final Uint8List bytes;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: title == null
            ? null
            : Text(title!, style: const TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 8,
          child: Image.memory(
            bytes,
            errorBuilder: (context, _, _) => const _NoPreview(),
          ),
        ),
      ),
    );
  }
}
