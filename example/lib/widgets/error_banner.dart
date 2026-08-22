import 'package:flutter/material.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

/// Renders any error thrown by a PixelCompressor call. Every native
/// method is currently a stub that throws `not_implemented`, so this is
/// what most demo actions will show today — it's called out explicitly
/// so it doesn't read as a bug.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asPixelError = error is PixelCompressorException
        ? error as PixelCompressorException
        : null;
    final isNotImplemented = asPixelError?.nativeCode == 'not_implemented';

    final title = isNotImplemented
        ? 'Not implemented on this platform yet'
        : asPixelError != null
        ? asPixelError.runtimeType.toString()
        : 'Unexpected error';
    final detail = asPixelError != null
        ? (asPixelError.nativeMessage ?? asPixelError.nativeCode)
        : '$error';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
                if (isNotImplemented) ...[
                  const SizedBox(height: 6),
                  Text(
                    "The Dart call went through correctly — this platform's native "
                    'compression engine just hasn\'t landed yet.',
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
