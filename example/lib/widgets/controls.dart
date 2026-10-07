import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'feature_layout.dart';
import 'headers.dart';

/// A card grouping related options under a small titled header.
class const OptionCard({
  super.key,
  required this.title,
  required this.icon,
  required this.children,
  this.trailing,
}) extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: Insets.md),
            ...spaced(children, gap: Insets.md - 2),
          ],
        ),
      ),
    );
  }
}

/// Collapsible "Advanced" section inside an [OptionCard].
class const AdvancedSection({
  super.key,
  required this.children,
  this.title = 'Advanced',
}) extends StatelessWidget {
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: .antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: Insets.md),
          childrenPadding: const .fromLTRB(Insets.md, 0, Insets.md, Insets.md),
          leading: Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
          title: Text(title, style: theme.textTheme.titleSmall),
          expandedCrossAxisAlignment: .stretch,
          children: spaced(children, gap: Insets.md - 2),
        ),
      ),
    );
  }
}

/// Label + current value on one line, slider below.
class const LabeledSlider({
  super.key,
  required this.label,
  required this.valueLabel,
  required this.value,
  required this.min,
  required this.max,
  required this.onChanged,
  this.divisions,
}) extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            ValuePill(valueLabel),
          ],
        ),
        const SizedBox(height: Insets.sm),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Small rounded value tag, tabular figures.
class const ValuePill(this.text, {super.key}) extends StatelessWidget {
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const .symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: .circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
          fontFeatures: tabular,
        ),
      ),
    );
  }
}

/// A switch row with an optional subtitle and platform hint.
class const OptionSwitch({
  super.key,
  required this.title,
  required this.value,
  required this.onChanged,
  this.subtitle,
  this.hint,
}) extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// When set, the switch is disabled and this explains why.
  final String? hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = hint ?? subtitle;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(title, style: theme.textTheme.bodyMedium),
              if (description != null)
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: Insets.sm),
        Switch(value: value, onChanged: hint == null ? onChanged : null),
      ],
    );
  }
}

class const Choice<T>(
  this.value,
  this.label, {
  this.icon,
  this.enabled = true,
}) {
  final T value;
  final String label;
  final IconData? icon;
  final bool enabled;
}

/// Label above a full-width single-select segmented button.
class const OptionSegmented<T>({
  super.key,
  required this.label,
  required this.choices,
  required this.selected,
  required this.onChanged,
  this.hint,
}) extends StatelessWidget {
  final String label;
  final List<Choice<T>> choices;
  final T selected;
  final ValueChanged<T>? onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Insets.sm),
        SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (final c in choices)
              ButtonSegment(
                value: c.value,
                label: FittedBox(fit: .scaleDown, child: Text(c.label)),
                icon: c.icon == null ? null : Icon(c.icon),
                enabled: c.enabled,
              ),
          ],
          selected: {selected},
          onSelectionChanged: onChanged == null
              ? null
              : (s) => onChanged!(s.first),
        ),
        if (hint != null) ...[
          const SizedBox(height: Insets.sm),
          PlatformHint(hint!),
        ],
      ],
    );
  }
}

/// Label + dropdown, for choices with too many options for segments.
class const OptionDropdown<T>({
  super.key,
  required this.label,
  required this.choices,
  required this.selected,
  required this.onChanged,
}) extends StatelessWidget {
  final String label;
  final List<Choice<T>> choices;
  final T selected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: selected,
      isExpanded: true,
      borderRadius: BorderRadius.circular(Insets.controlRadius),
      decoration: InputDecoration(labelText: label),
      items: [
        for (final c in choices)
          DropdownMenuItem(value: c.value, child: Text(c.label)),
      ],
      onChanged: onChanged == null
          ? null
          : (v) {
              if (v != null) onChanged!(v);
            },
    );
  }
}
