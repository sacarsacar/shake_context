# Plan 07 — Localization of `ProductionView`

## Goal

Make every user-facing string in the production sheet overridable so the package can ship in non-English apps. Currently `ProductionConfig` exposes 4 strings (`title`, `hintText`, `submitLabel`, `privacyNote`) but `ProductionView` hardcodes ~20 more.

Out of scope: `DeveloperView` localization. Engineer audience, English is defensible. Add `DeveloperStrings` later if users ask.

## API design

New `ProductionStrings` value class — one cohesive object for all production-sheet copy. `ProductionConfig` grows a `strings` field; the existing 4 top-level string fields stay (non-breaking) but are softly deprecated with a `@Deprecated` pointer to `strings.…`.

```dart
class ProductionStrings {
  const ProductionStrings({
    this.title = 'Report an Issue',
    this.hintText = 'What went wrong? Describe it here...',
    this.submitLabel = 'Send',
    this.cancelLabel = 'Cancel',
    this.privacyNote =
        'We include your device model and the time of the report to help us reproduce the issue.',
    this.headerSubtitle = "We'll read every word.",
    this.descriptionPrompt = 'What happened?',
    this.attachmentsLabel = 'Attachments',
    this.addImage = 'Add image',
    this.limitReached = 'Limit reached',
    this.noAttachments = 'No attachments.',
    this.addAttachmentHint = 'Add a screenshot to help us understand the issue.',
    this.sentWithReport = 'Sent with your report',
    this.timeLabel = 'Time',
    this.deviceLabel = 'Device',
    this.resolvingDeviceInfo = 'Resolving device info…',
    this.showDetails = 'Show details',
    this.hideDetails = 'Hide details',
    this.dismissTooltip = 'Dismiss',
    this.removeImageTooltip = 'Remove image',
    this.annotateTooltip = 'Annotate',
    this.tapToView = 'Tap to view',
    this.autoBadge = 'Auto',
    this.submissionFailedMessage =
        "Couldn't send your report. Please try again.",
  });
  // copyWith, ==, hashCode for every field
}
```

`ProductionConfig` becomes:

```dart
class ProductionConfig {
  const ProductionConfig({
    this.strings = const ProductionStrings(),
    // existing non-string fields unchanged...
    @Deprecated('Use ProductionConfig(strings: ProductionStrings(title: …))')
    String? title,
    @Deprecated('Use ProductionConfig(strings: ProductionStrings(hintText: …))')
    String? hintText,
    @Deprecated('Use ProductionConfig(strings: ProductionStrings(submitLabel: …))')
    String? submitLabel,
    @Deprecated('Use ProductionConfig(strings: ProductionStrings(privacyNote: …))')
    String? privacyNote,
    // ...
  }) : strings = title != null || hintText != null /* … */
       ? strings.copyWith(title: title, hintText: hintText, /* … */)
       : strings;
}
```

Existing callers `ProductionConfig(title: 'Foo')` keep working unchanged.

Submission-failure SnackBar in [`production_view.dart`](../lib/src/presentation/production_view.dart) reads from `config.strings.submissionFailedMessage` instead of the hardcoded literal.

## Files

| Action | Path |
|--------|------|
| New | `lib/src/models/production_strings.dart` |
| Modified | `lib/src/models/config_options.dart` — add `strings` field, deprecate the 4 old string fields, route them through the constructor |
| Modified | `lib/src/presentation/production_view.dart` — replace ~25 string literals with `config.strings.…` |
| Modified | `lib/shake_context.dart` — export `ProductionStrings` |
| New | `test/models/production_strings_test.dart` — defaults, copyWith, equality |
| Modified | `test/models/config_options_test.dart` — confirm deprecated string fields still flow into `strings` |
| Modified | `test/presentation/production_view_test.dart` — add 1–2 tests verifying custom strings render |
| Modified | `README.md` — add a "Localization" subsection under Configuration with an example wiring `ProductionStrings` from the host's `AppLocalizations` |
| Modified | `CHANGELOG.md` — unreleased entry |

## Test plan

- `ProductionStrings` defaults match the existing hardcoded literals (no visual regression for current users)
- `ProductionStrings.copyWith` overrides only provided fields
- `ProductionStrings` equality + hashCode are value-based
- `ProductionConfig(title: 'X')` still results in `config.strings.title == 'X'` (deprecation back-compat)
- `ProductionConfig(strings: ProductionStrings(title: 'Y'))` results in `config.strings.title == 'Y'`
- `ProductionView` widget test: render with a custom `ProductionStrings`, verify the custom values appear on screen
- All 119 existing tests must remain green — no behavioral change for any caller using the old API

## Acceptance

- `flutter analyze` green
- `flutter test` green, all existing tests pass, +5 new tests minimum
- README "Localization" subsection demonstrates wiring `flutter_localizations` to `ProductionStrings`
- CHANGELOG records the addition and the deprecation

## Risks

- **Deprecation noise** — users on the old 4-field API see analyzer warnings. Mitigation: the deprecation message points directly to the replacement.
- **String drift** — easy to add a new hardcoded string in a future PR without adding it to `ProductionStrings`. Mitigation: a CONTRIBUTING note + grep-able convention.
