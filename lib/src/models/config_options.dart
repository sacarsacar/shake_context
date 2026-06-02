import 'production_strings.dart';
import 'report_theme.dart';

/// Copy and behavior knobs for [InspectMode.production] feedback flows.
class ProductionConfig {
  const ProductionConfig({
    ProductionStrings strings = const ProductionStrings(),
    @Deprecated(
        'Use ProductionConfig(strings: ProductionStrings(title: …)) instead.')
    String? title,
    @Deprecated(
        'Use ProductionConfig(strings: ProductionStrings(hintText: …)) instead.')
    String? hintText,
    @Deprecated(
        'Use ProductionConfig(strings: ProductionStrings(submitLabel: …)) instead.')
    String? submitLabel,
    @Deprecated(
        'Use ProductionConfig(strings: ProductionStrings(privacyNote: …)) instead.')
    String? privacyNote,
    this.allowGalleryUpload = true,
    this.allowScreenshotAttachment = true,
    this.captureDeviceInfo = true,
    this.maxImages = 2,
    this.screenshotPixelRatio = 3.0,
    this.theme,
  })  : assert(maxImages > 0, 'maxImages must be at least 1'),
        assert(screenshotPixelRatio > 0,
            'screenshotPixelRatio must be greater than 0'),
        _baseStrings = strings,
        _depTitle = title,
        _depHintText = hintText,
        _depSubmitLabel = submitLabel,
        _depPrivacyNote = privacyNote;

  // The constructor-provided strings, before deprecated overrides are layered
  // in. `strings` (below) folds the two together so consumers only see one
  // canonical surface.
  final ProductionStrings _baseStrings;
  final String? _depTitle;
  final String? _depHintText;
  final String? _depSubmitLabel;
  final String? _depPrivacyNote;

  /// Localizable copy for the production feedback sheet. Source of truth for
  /// every user-facing string rendered by `ProductionView`.
  ///
  /// Wire your app's localization layer (e.g. `flutter_localizations` +
  /// `AppLocalizations`) into a per-locale [ProductionStrings] and pass it
  /// here. See the README's "Localization" section for a worked example.
  ///
  /// For source compatibility, the deprecated top-level string parameters
  /// (`title`, `hintText`, `submitLabel`, `privacyNote`) are folded into this
  /// value if the caller still uses them.
  ProductionStrings get strings {
    if (_depTitle == null &&
        _depHintText == null &&
        _depSubmitLabel == null &&
        _depPrivacyNote == null) {
      return _baseStrings;
    }
    return _baseStrings.copyWith(
      title: _depTitle,
      hintText: _depHintText,
      submitLabel: _depSubmitLabel,
      privacyNote: _depPrivacyNote,
    );
  }

  /// Bottom-sheet header.
  @Deprecated('Use ProductionConfig.strings.title instead.')
  String get title => _depTitle ?? _baseStrings.title;

  /// Placeholder shown inside the description text field.
  @Deprecated('Use ProductionConfig.strings.hintText instead.')
  String get hintText => _depHintText ?? _baseStrings.hintText;

  /// Label on the submit button.
  @Deprecated('Use ProductionConfig.strings.submitLabel instead.')
  String get submitLabel => _depSubmitLabel ?? _baseStrings.submitLabel;

  /// Short reassurance line explaining what gets shared.
  @Deprecated('Use ProductionConfig.strings.privacyNote instead.')
  String get privacyNote => _depPrivacyNote ?? _baseStrings.privacyNote;

  /// When `true`, the production view exposes a `+` button to attach images
  /// from the device gallery.
  final bool allowGalleryUpload;

  /// When `true`, the production view captures a screenshot and offers it as
  /// a removable attachment. When `false`, no screenshot is captured at all.
  final bool allowScreenshotAttachment;

  /// When `true`, the production view captures basic device context (model,
  /// OS version, app version) via `device_info_plus` and shows it in a small
  /// disclosure card so the user can see what is being shared. Defaults to
  /// `true` — most support workflows need at least this much context to
  /// reproduce an issue. Turn off for fully anonymous reports.
  ///
  /// Console logs, network traffic, and the current route are never captured
  /// in production mode regardless of this flag.
  final bool captureDeviceInfo;

  /// Maximum number of images the user can include in a single report.
  ///
  /// The auto-captured screenshot (when [allowScreenshotAttachment] is on)
  /// counts toward this cap. Defaults to `2` to keep upload payloads small;
  /// raise it if your support channel can absorb more attachments.
  final int maxImages;

  /// Device-pixel ratio used when rasterising the auto-captured screenshot.
  ///
  /// Defaults to `3.0` — visually sharp on every modern display, but on a
  /// 1080p phone the resulting PNG can land in the 5–8 MB range. Dial down
  /// to `1.5`–`2.0` when your support channel is sensitive to upload size,
  /// or when you intend to recompress server-side anyway.
  ///
  /// Ignored when [allowScreenshotAttachment] is `false`.
  final double screenshotPixelRatio;

  /// Optional color overrides applied to the production report surface. Any
  /// field left null on the [ReportTheme] falls back to the inherited
  /// Material `colorScheme`.
  final ReportTheme? theme;

  ProductionConfig copyWith({
    ProductionStrings? strings,
    @Deprecated(
        'Use copyWith(strings: ProductionStrings(title: …)) instead.')
    String? title,
    @Deprecated(
        'Use copyWith(strings: ProductionStrings(hintText: …)) instead.')
    String? hintText,
    @Deprecated(
        'Use copyWith(strings: ProductionStrings(submitLabel: …)) instead.')
    String? submitLabel,
    @Deprecated(
        'Use copyWith(strings: ProductionStrings(privacyNote: …)) instead.')
    String? privacyNote,
    bool? allowGalleryUpload,
    bool? allowScreenshotAttachment,
    bool? captureDeviceInfo,
    int? maxImages,
    double? screenshotPixelRatio,
    ReportTheme? theme,
  }) {
    // Collapse the current effective strings into the new base, then layer
    // any provided overrides on top. This keeps `copyWith(title: 'X')`
    // behaving exactly as before for legacy callers.
    final base = strings ?? this.strings;
    return ProductionConfig(
      strings: base,
      // ignore: deprecated_member_use_from_same_package
      title: title,
      // ignore: deprecated_member_use_from_same_package
      hintText: hintText,
      // ignore: deprecated_member_use_from_same_package
      submitLabel: submitLabel,
      // ignore: deprecated_member_use_from_same_package
      privacyNote: privacyNote,
      allowGalleryUpload: allowGalleryUpload ?? this.allowGalleryUpload,
      allowScreenshotAttachment:
          allowScreenshotAttachment ?? this.allowScreenshotAttachment,
      captureDeviceInfo: captureDeviceInfo ?? this.captureDeviceInfo,
      maxImages: maxImages ?? this.maxImages,
      screenshotPixelRatio:
          screenshotPixelRatio ?? this.screenshotPixelRatio,
      theme: theme ?? this.theme,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProductionConfig &&
        other.strings == strings &&
        other.allowGalleryUpload == allowGalleryUpload &&
        other.allowScreenshotAttachment == allowScreenshotAttachment &&
        other.captureDeviceInfo == captureDeviceInfo &&
        other.maxImages == maxImages &&
        other.screenshotPixelRatio == screenshotPixelRatio &&
        other.theme == theme;
  }

  @override
  int get hashCode => Object.hash(
        strings,
        allowGalleryUpload,
        allowScreenshotAttachment,
        captureDeviceInfo,
        maxImages,
        screenshotPixelRatio,
        theme,
      );
}

/// Diagnostic capture toggles for [InspectMode.developer].
class DeveloperConfig {
  const DeveloperConfig({
    this.captureRoute = true,
    this.captureDeviceInfo = true,
    this.captureConsoleLogs = true,
    this.captureNetworkLogs = true,
    this.captureScreenshot = true,
    this.logBufferSize = 200,
    this.networkBufferSize = 50,
    this.screenshotPixelRatio = 3.0,
    this.theme,
  }) : assert(screenshotPixelRatio > 0,
            'screenshotPixelRatio must be greater than 0');

  /// Capture the current route name from the active [Navigator].
  final bool captureRoute;

  /// Capture device model / OS / RAM via `device_info_plus`.
  final bool captureDeviceInfo;

  /// Drain the captured log buffer (`print`, `debugPrint`, framework errors,
  /// `ShakeContext.log(...)` entries) into the report.
  final bool captureConsoleLogs;

  /// Drain the captured HTTP cycle buffer (populated by
  /// `ShakeDioInterceptor` or a host adapter) into the report.
  final bool captureNetworkLogs;

  /// Snapshot the visible render tree on shake.
  final bool captureScreenshot;

  /// Maximum log entries retained in the rolling buffer.
  final int logBufferSize;

  /// Maximum network entries retained in the rolling buffer.
  final int networkBufferSize;

  /// Device-pixel ratio used when rasterising the auto-captured screenshot.
  ///
  /// Defaults to `3.0` — visually sharp on every modern display, but on a
  /// 1080p phone the resulting PNG can land in the 5–8 MB range. Dial down
  /// to `1.5`–`2.0` when your QA channel is sensitive to upload size.
  ///
  /// Ignored when [captureScreenshot] is `false`.
  final double screenshotPixelRatio;

  /// Optional color overrides applied to the developer report surface. Any
  /// field left null on the [ReportTheme] falls back to the inherited
  /// Material `colorScheme`.
  final ReportTheme? theme;

  DeveloperConfig copyWith({
    bool? captureRoute,
    bool? captureDeviceInfo,
    bool? captureConsoleLogs,
    bool? captureNetworkLogs,
    bool? captureScreenshot,
    int? logBufferSize,
    int? networkBufferSize,
    double? screenshotPixelRatio,
    ReportTheme? theme,
  }) {
    return DeveloperConfig(
      captureRoute: captureRoute ?? this.captureRoute,
      captureDeviceInfo: captureDeviceInfo ?? this.captureDeviceInfo,
      captureConsoleLogs: captureConsoleLogs ?? this.captureConsoleLogs,
      captureNetworkLogs: captureNetworkLogs ?? this.captureNetworkLogs,
      captureScreenshot: captureScreenshot ?? this.captureScreenshot,
      logBufferSize: logBufferSize ?? this.logBufferSize,
      networkBufferSize: networkBufferSize ?? this.networkBufferSize,
      screenshotPixelRatio:
          screenshotPixelRatio ?? this.screenshotPixelRatio,
      theme: theme ?? this.theme,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeveloperConfig &&
        other.captureRoute == captureRoute &&
        other.captureDeviceInfo == captureDeviceInfo &&
        other.captureConsoleLogs == captureConsoleLogs &&
        other.captureNetworkLogs == captureNetworkLogs &&
        other.captureScreenshot == captureScreenshot &&
        other.logBufferSize == logBufferSize &&
        other.networkBufferSize == networkBufferSize &&
        other.screenshotPixelRatio == screenshotPixelRatio &&
        other.theme == theme;
  }

  @override
  int get hashCode => Object.hash(
        captureRoute,
        captureDeviceInfo,
        captureConsoleLogs,
        captureNetworkLogs,
        captureScreenshot,
        logBufferSize,
        networkBufferSize,
        screenshotPixelRatio,
        theme,
      );
}
