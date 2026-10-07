import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Inserts [gap] between [children].
List<Widget> spaced(Iterable<Widget> children, {double gap = Insets.md}) {
  final out = <Widget>[];
  for (final child in children) {
    if (out.isNotEmpty) out.add(SizedBox(height: gap, width: gap));
    out.add(child);
  }
  return out;
}

/// The layout every tab uses: hero header, then either an empty state or the
/// source preview, option cards and result, with a sticky action bar.
///
/// Phones get one scrolling column. From [Insets.wideBreakpoint] up, options
/// go in the left pane and preview + result in the right one.
class const FeatureLayout({
  super.key,
  required this.header,
  this.empty,
  this.preview = const [],
  this.options = const [],
  this.result,
  this.actions,
}) extends StatelessWidget {
  final Widget header;

  /// Shown instead of preview/options/result while there's nothing to work on.
  final Widget? empty;
  final List<Widget> preview;
  final List<Widget> options;
  final Widget? result;
  final Widget? actions;

  static const _padding = EdgeInsets.fromLTRB(
    Insets.md,
    Insets.sm,
    Insets.md,
    Insets.xl,
  );

  @override
  Widget build(BuildContext context) {
    final animatedResult = AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: .topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: result ?? const SizedBox(width: double.infinity),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Insets.wideBreakpoint;
        final Widget content;
        final empty = this.empty;
        if (empty != null) {
          content = _column([header, empty], maxWidth: 720);
        } else if (!wide) {
          content = _column([
            header,
            ...preview,
            ...options,
            animatedResult,
          ], maxWidth: 720);
        } else {
          content = Row(
            crossAxisAlignment: .start,
            children: [
              Expanded(flex: 5, child: _column([header, ...options])),
              Expanded(
                flex: 6,
                child: _column([
                  if (preview.isEmpty && result == null)
                    const _ResultPlaceholder(),
                  ...preview,
                  animatedResult,
                ], top: Insets.lg + Insets.sm),
              ),
            ],
          );
        }
        final actions = this.actions;
        return Column(
          children: [
            Expanded(child: content),
            if (actions != null && empty == null) ActionBar(child: actions),
          ],
        );
      },
    );
  }

  Widget _column(List<Widget> children, {double? maxWidth, double? top}) {
    final list = ListView(
      padding: top == null ? _padding : _padding.copyWith(top: top),
      children: spaced(children),
    );
    if (maxWidth == null) return list;
    return Align(
      alignment: .topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: list,
      ),
    );
  }
}

class const _ResultPlaceholder() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 220,
      alignment: .center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Insets.cardRadius),
        border: .all(color: scheme.outlineVariant),
      ),
      child: Text(
        'The result appears here',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// Sticky bottom bar holding a tab's primary actions.
class const ActionBar({super.key, required this.child})
    extends StatelessWidget {
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const .fromLTRB(
            Insets.md,
            Insets.md - 4,
            Insets.md,
            Insets.md - 4,
          ),
          child: Align(
            alignment: .center,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SizedBox(width: double.infinity, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary action button that shows an inline spinner while [busy].
class const BusyButton({
  super.key,
  required this.label,
  required this.icon,
  required this.busy,
  required this.onPressed,
}) extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: busy
            ? SizedBox.square(
                key: const ValueKey('busy'),
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : Icon(icon, key: const ValueKey('idle')),
      ),
      label: Text(label),
    );
  }
}
