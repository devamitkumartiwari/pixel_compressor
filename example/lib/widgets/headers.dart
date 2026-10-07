import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tab title: tinted icon badge, title and a one-line description.
class const HeroHeader({
  super.key,
  required this.icon,
  required this.title,
  required this.subtitle,
  this.trailing,
}) extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Insets.md),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: .topLeft,
                end: .bottomRight,
                colors: [scheme.primary, scheme.tertiary],
              ),
              borderRadius: .circular(16),
            ),
            child: Icon(icon, color: scheme.onPrimary, size: 26),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Insets.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Large friendly placeholder shown before anything is picked.
class const EmptyState({
  super.key,
  required this.icon,
  required this.title,
  required this.message,
  this.actions = const [],
}) extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const .symmetric(
        horizontal: Insets.lg,
        vertical: Insets.xl + Insets.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Insets.cardRadius + 8),
        border: .all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              shape: .circle,
            ),
            child: Icon(icon, size: 40, color: scheme.primary),
          ),
          const SizedBox(height: Insets.lg),
          Text(title, style: theme.textTheme.titleLarge, textAlign: .center),
          const SizedBox(height: Insets.sm),
          Text(
            message,
            textAlign: .center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: Insets.lg),
            Wrap(
              spacing: Insets.sm + 4,
              runSpacing: Insets.sm + 4,
              alignment: .center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// Small "not on this platform" style note.
class const PlatformHint(this.text, {super.key}) extends StatelessWidget {
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
