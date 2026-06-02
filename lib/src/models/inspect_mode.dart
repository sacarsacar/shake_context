import 'package:flutter/foundation.dart';

/// Operating mode for [ShakeContext].
///
/// Switches the entire engine between a high-density developer diagnostic
/// experience and a privacy-respecting production feedback flow.
enum InspectMode {
  /// Automated diagnostics for engineers, QA, and beta testers.
  ///
  /// Captures screenshots, device info, route, and console logs without
  /// asking the user.
  developer,

  /// Privacy-first manual feedback flow for production consumers.
  ///
  /// Collects only user-typed text and user-approved attachments.
  production;

  /// Pick the right [InspectMode] for the current build.
  ///
  /// Codifies the convention the README quick-start uses, and adds first-
  /// class support for projects that ship multiple build flavors.
  ///
  /// **Without flavors** — call with no arguments:
  ///
  /// ```dart
  /// ShakeContext(
  ///   mode: InspectMode.resolve(),
  ///   onReportSubmitted: ...,
  ///   child: const MyApp(),
  /// )
  /// ```
  ///
  /// Equivalent to `kReleaseMode ? production : developer`. Debug and
  /// profile builds show the diagnostic overlay; release builds show the
  /// consumer feedback sheet.
  ///
  /// **With flavors** — pass the active flavor identifier from your
  /// per-flavor entry point (e.g. `main_dev.dart`, `main_prod.dart`):
  ///
  /// ```dart
  /// ShakeContext(
  ///   mode: InspectMode.resolve(flavor: 'dev'),
  ///   ...
  /// )
  /// ```
  ///
  /// Returns [production] only when the build is a release build **and**
  /// [flavor] is in [productionFlavors]. Every other combination —
  /// including a release build of the `dev` flavor (e.g. an internal
  /// TestFlight track) — returns [developer]. This lets QA keep the
  /// diagnostic overlay on signed builds without exposing it to real
  /// consumers.
  ///
  /// [productionFlavors] defaults to `{'prod', 'production'}`. Override
  /// it for projects that use different naming (`'release'`, `'live'`,
  /// `'appstore'`, …):
  ///
  /// ```dart
  /// mode: InspectMode.resolve(
  ///   flavor: appFlavor,
  ///   productionFlavors: {'live', 'appstore'},
  /// ),
  /// ```
  ///
  /// [isReleaseBuild] is an injectable override used by the package's own
  /// tests. Production code should leave it `null`, in which case the
  /// value of [kReleaseMode] is read.
  static InspectMode resolve({
    String? flavor,
    Set<String> productionFlavors = const {'prod', 'production'},
    bool? isReleaseBuild,
  }) {
    final isRelease = isReleaseBuild ?? kReleaseMode;
    if (flavor == null) {
      return isRelease ? InspectMode.production : InspectMode.developer;
    }
    final isProductionAudience =
        isRelease && productionFlavors.contains(flavor);
    return isProductionAudience
        ? InspectMode.production
        : InspectMode.developer;
  }
}
