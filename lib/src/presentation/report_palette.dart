import 'package:flutter/material.dart';

import '../models/report_theme.dart';

/// Internal: resolves a [ReportTheme] against the inherited Material theme,
/// filling in any unset slots with `colorScheme` defaults. Shared between the
/// developer and production views.
@immutable
class ReportPalette {
  const ReportPalette({
    required this.background,
    required this.card,
    required this.border,
    required this.primary,
    required this.onPrimary,
    required this.text,
    required this.subtitle,
    required this.submitBackground,
    required this.submitForeground,
    required this.cancelForeground,
  });

  factory ReportPalette.resolve(BuildContext context, ReportTheme? overrides) {
    final cs = Theme.of(context).colorScheme;
    final primary = overrides?.primaryColor ?? cs.primary;
    final onPrimary = overrides?.onPrimaryColor ?? cs.onPrimary;
    return ReportPalette(
      background: overrides?.backgroundColor ?? cs.surface,
      card: overrides?.cardColor ?? cs.surfaceContainerLow,
      border: overrides?.borderColor ?? cs.outlineVariant,
      primary: primary,
      onPrimary: onPrimary,
      text: overrides?.textColor ?? cs.onSurface,
      subtitle: overrides?.subtitleColor ?? cs.onSurfaceVariant,
      submitBackground: overrides?.submitButtonColor ?? primary,
      submitForeground: overrides?.submitButtonTextColor ?? onPrimary,
      cancelForeground: overrides?.cancelButtonColor ?? primary,
    );
  }

  final Color background;
  final Color card;
  final Color border;
  final Color primary;
  final Color onPrimary;
  final Color text;
  final Color subtitle;
  final Color submitBackground;
  final Color submitForeground;
  final Color cancelForeground;
}
