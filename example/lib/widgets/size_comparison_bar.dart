import 'package:flutter/material.dart';

import '../utils/format.dart';

/// Two proportional bars showing original vs. compressed size, plus the
/// percent saved — the "at which level and size" view for a single result.
class SizeComparisonBar extends StatelessWidget {
  const SizeComparisonBar({
    super.key,
    required this.originalBytes,
    required this.outputBytes,
  });

  final int originalBytes;
  final int outputBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxBytes = originalBytes > outputBytes ? originalBytes : outputBytes;
    final savedPercent = originalBytes == 0
        ? 0.0
        : ((originalBytes - outputBytes) / originalBytes) * 100;

    Widget bar(String label, int bytes, Color color) {
      final fraction = maxBytes == 0 ? 0.0 : bytes / maxBytes;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ${formatBytes(bytes)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction.clamp(0.02, 1.0),
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      );
    }

    final savedColor = theme.brightness == Brightness.dark
        ? Colors.greenAccent.shade200
        : Colors.green.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar(
          'Original',
          originalBytes,
          theme.colorScheme.error.withValues(alpha: 0.65),
        ),
        const SizedBox(height: 10),
        bar('Compressed', outputBytes, theme.colorScheme.primary),
        const SizedBox(height: 10),
        Text(
          savedPercent >= 0
              ? '${formatPercent(savedPercent)} smaller'
              : '${formatPercent(-savedPercent)} larger',
          style: theme.textTheme.titleMedium?.copyWith(
            color: savedPercent >= 0 ? savedColor : theme.colorScheme.error,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
