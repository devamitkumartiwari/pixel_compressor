import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Card framing a finished operation's output.
class const ResultCard({
  super.key,
  required this.title,
  required this.children,
  this.icon = Icons.check_circle_rounded,
  this.trailing,
}) extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Insets.cardRadius),
        side: BorderSide(color: palette.success.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: palette.success),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: Insets.md),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: Insets.md),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Card showing the picked input: a preview, facts about it, and a button to
/// pick something else.
class const SourceCard({
  super.key,
  required this.title,
  required this.chips,
  this.preview,
  this.onChange,
}) extends StatelessWidget {
  final String title;
  final Widget? preview;
  final List<Widget> chips;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.sm + 4),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            if (preview != null) ...[
              preview!,
              const SizedBox(height: Insets.sm + 4),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (onChange != null)
                  TextButton.icon(
                    onPressed: onChange,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Change'),
                  ),
              ],
            ),
            const SizedBox(height: Insets.xs),
            StatChips(chips),
          ],
        ),
      ),
    );
  }
}

/// Big "−72 %" pill: how much smaller (or larger) the output is.
class const SavingsBadge({
  super.key,
  required this.originalBytes,
  required this.outputBytes,
}) extends StatelessWidget {
  final int originalBytes;
  final int outputBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final scheme = theme.colorScheme;
    final saved = originalBytes == 0
        ? 0.0
        : (originalBytes - outputBytes) / originalBytes * 100;
    final smaller = saved >= 0;
    final bg = smaller ? palette.successContainer : scheme.errorContainer;
    final fg = smaller ? palette.onSuccessContainer : scheme.onErrorContainer;

    return Container(
      padding: const .symmetric(horizontal: Insets.md, vertical: Insets.md - 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Insets.cardRadius - 4),
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: saved.abs()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              '${smaller ? '−' : '+'}${value.toStringAsFixed(0)}%',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: fg,
                fontFeatures: tabular,
              ),
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  smaller ? 'smaller' : 'larger',
                  style: theme.textTheme.titleSmall?.copyWith(color: fg),
                ),
                Text(
                  '${formatBytes(originalBytes)} → ${formatBytes(outputBytes)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: fg.withValues(alpha: 0.8),
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two proportional bars: original vs. output size.
class const SizeComparisonBar({
  super.key,
  required this.originalBytes,
  required this.outputBytes,
}) extends StatelessWidget {
  final int originalBytes;
  final int outputBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxBytes = originalBytes > outputBytes ? originalBytes : outputBytes;

    Widget bar(String label, int bytes, Color color) {
      final fraction = maxBytes == 0 ? 0.0 : bytes / maxBytes;
      return Column(
        crossAxisAlignment: .start,
        children: [
          Row(
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const Spacer(),
              Text(
                formatBytes(bytes),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: .circular(999),
            child: Stack(
              children: [
                Container(height: 10, color: scheme.surfaceContainerHighest),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fraction.clamp(0.02, 1.0)),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => FractionallySizedBox(
                    widthFactor: value,
                    child: Container(height: 10, color: color),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        bar('Original', originalBytes, scheme.outline),
        const SizedBox(height: Insets.sm + 4),
        bar('Compressed', outputBytes, scheme.primary),
      ],
    );
  }
}

/// Small icon + text tag for one fact about a result.
class const StatChip({super.key, required this.icon, required this.label})
    extends StatelessWidget {
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const .symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: .circular(999),
      ),
      child: Row(
        mainAxisSize: .min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: .ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontFeatures: tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class const StatChips(this.chips, {super.key}) extends StatelessWidget {
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: Insets.sm, runSpacing: Insets.sm, children: chips);
}

/// Key/value rows, e.g. media info fields.
class const InfoTable(this.rows, {super.key}) extends StatelessWidget {
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(),
          Padding(
            padding: const .symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: .start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    rows[i].$1,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    rows[i].$2,
                    textAlign: .end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
