import 'package:flutter/widgets.dart';

/// Optional color overrides for the developer and production report surfaces.
///
/// Pass an instance to [DeveloperConfig.theme] and/or [ProductionConfig.theme]
/// to recolor the report sheet without having to provide a full Flutter
/// [ThemeData]. Every field is nullable — any field left `null` falls back to
/// the corresponding token on the inherited [Theme]'s `colorScheme`, so you
/// can override just the colors you care about.
@immutable
class ReportTheme {
  const ReportTheme({
    this.backgroundColor,
    this.cardColor,
    this.borderColor,
    this.primaryColor,
    this.onPrimaryColor,
    this.textColor,
    this.subtitleColor,
    this.submitButtonColor,
    this.submitButtonTextColor,
    this.cancelButtonColor,
  });

  /// Modal sheet background (defaults to `colorScheme.surface`).
  final Color? backgroundColor;

  /// Section cards and the description/note text-field fill
  /// (defaults to `colorScheme.surfaceContainerLow`).
  final Color? cardColor;

  /// Section borders and idle text-field borders
  /// (defaults to `colorScheme.outlineVariant`).
  final Color? borderColor;

  /// Accent color: header icon chip background, section icons, focused
  /// text-field border (defaults to `colorScheme.primary`).
  final Color? primaryColor;

  /// Foreground color on top of [primaryColor] — header icon, submit button
  /// label (defaults to `colorScheme.onPrimary`).
  final Color? onPrimaryColor;

  /// Primary text color for titles, body text, and diagnostic values
  /// (defaults to `colorScheme.onSurface`).
  final Color? textColor;

  /// Secondary text color for labels, hints, and helper rows
  /// (defaults to `colorScheme.onSurfaceVariant`).
  final Color? subtitleColor;

  /// Submit / Send button background. Falls back to [primaryColor], then
  /// `colorScheme.primary`.
  final Color? submitButtonColor;

  /// Submit / Send button label color. Falls back to [onPrimaryColor], then
  /// `colorScheme.onPrimary`.
  final Color? submitButtonTextColor;

  /// Cancel (outlined) button text and border color. Falls back to
  /// [primaryColor], then `colorScheme.primary`.
  final Color? cancelButtonColor;

  ReportTheme copyWith({
    Color? backgroundColor,
    Color? cardColor,
    Color? borderColor,
    Color? primaryColor,
    Color? onPrimaryColor,
    Color? textColor,
    Color? subtitleColor,
    Color? submitButtonColor,
    Color? submitButtonTextColor,
    Color? cancelButtonColor,
  }) {
    return ReportTheme(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      cardColor: cardColor ?? this.cardColor,
      borderColor: borderColor ?? this.borderColor,
      primaryColor: primaryColor ?? this.primaryColor,
      onPrimaryColor: onPrimaryColor ?? this.onPrimaryColor,
      textColor: textColor ?? this.textColor,
      subtitleColor: subtitleColor ?? this.subtitleColor,
      submitButtonColor: submitButtonColor ?? this.submitButtonColor,
      submitButtonTextColor:
          submitButtonTextColor ?? this.submitButtonTextColor,
      cancelButtonColor: cancelButtonColor ?? this.cancelButtonColor,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReportTheme &&
        other.backgroundColor == backgroundColor &&
        other.cardColor == cardColor &&
        other.borderColor == borderColor &&
        other.primaryColor == primaryColor &&
        other.onPrimaryColor == onPrimaryColor &&
        other.textColor == textColor &&
        other.subtitleColor == subtitleColor &&
        other.submitButtonColor == submitButtonColor &&
        other.submitButtonTextColor == submitButtonTextColor &&
        other.cancelButtonColor == cancelButtonColor;
  }

  @override
  int get hashCode => Object.hash(
        backgroundColor,
        cardColor,
        borderColor,
        primaryColor,
        onPrimaryColor,
        textColor,
        subtitleColor,
        submitButtonColor,
        submitButtonTextColor,
        cancelButtonColor,
      );
}
