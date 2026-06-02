/// User-facing copy for the production feedback sheet.
///
/// Every visible string in `ProductionView` is sourced from an instance of
/// this class so hosts can swap in translations. The defaults match the
/// English copy the package historically shipped with — passing no `strings`
/// to `ProductionConfig` keeps the current wording intact.
///
/// Typical wiring uses your app's existing localization layer
/// (e.g. `flutter_localizations` + an `AppLocalizations` class) to populate
/// these fields per locale; see the README's "Localization" section for a
/// worked example.
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
    this.addAttachmentHint =
        'Add a screenshot to help us understand the issue.',
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

  /// Bottom-sheet header.
  final String title;

  /// Placeholder shown inside the description text field.
  final String hintText;

  /// Label on the submit button.
  final String submitLabel;

  /// Label on the cancel button.
  final String cancelLabel;

  /// Short reassurance line explaining what gets shared.
  final String privacyNote;

  /// Sub-line under the header title.
  final String headerSubtitle;

  /// Section label above the description field.
  final String descriptionPrompt;

  /// Base label for the attachments section. Count and cap are appended at
  /// render time (e.g. `Attachments (1/2)`).
  final String attachmentsLabel;

  /// "Add image" button label.
  final String addImage;

  /// Shown next to the attachments label when the cap has been hit.
  final String limitReached;

  /// Shown in the empty attachments slot when gallery picking is disabled.
  final String noAttachments;

  /// Shown in the empty attachments slot when gallery picking is available.
  final String addAttachmentHint;

  /// Heading on the "what we'll send" disclosure card.
  final String sentWithReport;

  /// Row label for the trigger timestamp.
  final String timeLabel;

  /// Row label for the device-info digest.
  final String deviceLabel;

  /// Italic placeholder shown on the device row while `deviceInfoFuture` is
  /// still resolving.
  final String resolvingDeviceInfo;

  /// "Show details" toggle on the disclosure card.
  final String showDetails;

  /// "Hide details" toggle on the disclosure card.
  final String hideDetails;

  /// Tooltip on the close (×) button in the header.
  final String dismissTooltip;

  /// Tooltip on the remove-attachment (×) badge.
  final String removeImageTooltip;

  /// Tooltip on the per-attachment edit icon.
  final String annotateTooltip;

  /// Caption pill on each attachment tile.
  final String tapToView;

  /// "Auto" badge shown on the auto-captured screenshot tile.
  final String autoBadge;

  /// Generic SnackBar message when `onReportSubmitted` throws.
  final String submissionFailedMessage;

  ProductionStrings copyWith({
    String? title,
    String? hintText,
    String? submitLabel,
    String? cancelLabel,
    String? privacyNote,
    String? headerSubtitle,
    String? descriptionPrompt,
    String? attachmentsLabel,
    String? addImage,
    String? limitReached,
    String? noAttachments,
    String? addAttachmentHint,
    String? sentWithReport,
    String? timeLabel,
    String? deviceLabel,
    String? resolvingDeviceInfo,
    String? showDetails,
    String? hideDetails,
    String? dismissTooltip,
    String? removeImageTooltip,
    String? annotateTooltip,
    String? tapToView,
    String? autoBadge,
    String? submissionFailedMessage,
  }) {
    return ProductionStrings(
      title: title ?? this.title,
      hintText: hintText ?? this.hintText,
      submitLabel: submitLabel ?? this.submitLabel,
      cancelLabel: cancelLabel ?? this.cancelLabel,
      privacyNote: privacyNote ?? this.privacyNote,
      headerSubtitle: headerSubtitle ?? this.headerSubtitle,
      descriptionPrompt: descriptionPrompt ?? this.descriptionPrompt,
      attachmentsLabel: attachmentsLabel ?? this.attachmentsLabel,
      addImage: addImage ?? this.addImage,
      limitReached: limitReached ?? this.limitReached,
      noAttachments: noAttachments ?? this.noAttachments,
      addAttachmentHint: addAttachmentHint ?? this.addAttachmentHint,
      sentWithReport: sentWithReport ?? this.sentWithReport,
      timeLabel: timeLabel ?? this.timeLabel,
      deviceLabel: deviceLabel ?? this.deviceLabel,
      resolvingDeviceInfo: resolvingDeviceInfo ?? this.resolvingDeviceInfo,
      showDetails: showDetails ?? this.showDetails,
      hideDetails: hideDetails ?? this.hideDetails,
      dismissTooltip: dismissTooltip ?? this.dismissTooltip,
      removeImageTooltip: removeImageTooltip ?? this.removeImageTooltip,
      annotateTooltip: annotateTooltip ?? this.annotateTooltip,
      tapToView: tapToView ?? this.tapToView,
      autoBadge: autoBadge ?? this.autoBadge,
      submissionFailedMessage:
          submissionFailedMessage ?? this.submissionFailedMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProductionStrings &&
        other.title == title &&
        other.hintText == hintText &&
        other.submitLabel == submitLabel &&
        other.cancelLabel == cancelLabel &&
        other.privacyNote == privacyNote &&
        other.headerSubtitle == headerSubtitle &&
        other.descriptionPrompt == descriptionPrompt &&
        other.attachmentsLabel == attachmentsLabel &&
        other.addImage == addImage &&
        other.limitReached == limitReached &&
        other.noAttachments == noAttachments &&
        other.addAttachmentHint == addAttachmentHint &&
        other.sentWithReport == sentWithReport &&
        other.timeLabel == timeLabel &&
        other.deviceLabel == deviceLabel &&
        other.resolvingDeviceInfo == resolvingDeviceInfo &&
        other.showDetails == showDetails &&
        other.hideDetails == hideDetails &&
        other.dismissTooltip == dismissTooltip &&
        other.removeImageTooltip == removeImageTooltip &&
        other.annotateTooltip == annotateTooltip &&
        other.tapToView == tapToView &&
        other.autoBadge == autoBadge &&
        other.submissionFailedMessage == submissionFailedMessage;
  }

  @override
  int get hashCode => Object.hashAll([
        title,
        hintText,
        submitLabel,
        cancelLabel,
        privacyNote,
        headerSubtitle,
        descriptionPrompt,
        attachmentsLabel,
        addImage,
        limitReached,
        noAttachments,
        addAttachmentHint,
        sentWithReport,
        timeLabel,
        deviceLabel,
        resolvingDeviceInfo,
        showDetails,
        hideDetails,
        dismissTooltip,
        removeImageTooltip,
        annotateTooltip,
        tapToView,
        autoBadge,
        submissionFailedMessage,
      ]);
}
