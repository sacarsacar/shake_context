import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/retry_queue.dart';
import '../models/config_options.dart';
import '../models/inspect_mode.dart';
import '../models/report_payload.dart';
import 'developer_view.dart';
import 'production_view.dart';

/// Launches the correct feedback surface for the active [InspectMode].
///
/// The launcher itself is stateless — the per-mode views own their internal
/// UI state, including resolving any in-flight capture futures.
class UnifiedOverlay {
  const UnifiedOverlay._();

  /// Show the production sheet ([InspectMode.production]) or developer sheet
  /// ([InspectMode.developer]). Returns when the sheet is dismissed.
  ///
  /// Async capture results can be supplied as [screenshotFuture] and
  /// [deviceInfoFuture]; the view rebuilds when each resolves, so the sheet
  /// opens instantly while capture runs in the background.
  static Future<void> show({
    required BuildContext context,
    required InspectMode mode,
    required ProductionConfig productionConfig,
    required DeveloperConfig developerConfig,
    required ReportSubmittedCallback onSubmit,
    ReportMetadata? metadata,
    Uint8List? screenshot,
    Future<Uint8List?>? screenshotFuture,
    Future<Map<String, Object?>>? deviceInfoFuture,
    ImagePickerCallback? onPickImage,
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    final sheetBackground = switch (mode) {
      InspectMode.developer => developerConfig.theme?.backgroundColor,
      InspectMode.production => productionConfig.theme?.backgroundColor,
    };

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: sheetBackground,
      builder: (sheetContext) {
        // The host's callback runs first; if it returns normally we pop.
        // If it throws, we surface the failure to the view layer (which
        // shows a SnackBar) without dismissing the sheet — the user's typed
        // text and attachments must survive a transport failure so they can
        // retry. Submission errors are not swallowed silently because that
        // is the worst UX outcome: spinner clears, no signal, lost report.
        //
        // When the retry queue is enabled, a failed payload is enqueued to
        // disk *before* the error propagates back to the view, so the user
        // can dismiss the sheet without losing the report — the next launch
        // (or a manual `replayQueuedReports()` call) will retry it.
        Future<void> wrappedSubmit(ReportPayload payload) async {
          try {
            await onSubmit(payload);
          } catch (_) {
            await RetryQueue.instance?.enqueue(payload);
            rethrow;
          }
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        }

        switch (mode) {
          case InspectMode.developer:
            return DeveloperView(
              config: developerConfig,
              metadata: metadata ?? ReportMetadata.empty(),
              screenshot: screenshot,
              screenshotFuture: screenshotFuture,
              deviceInfoFuture: deviceInfoFuture,
              extras: extras,
              onSubmit: wrappedSubmit,
            );
          case InspectMode.production:
            return ProductionView(
              config: productionConfig,
              metadata: metadata ?? ReportMetadata.empty(),
              initialScreenshot: screenshot,
              initialScreenshotFuture: screenshotFuture,
              deviceInfoFuture: deviceInfoFuture,
              onPickImage: onPickImage,
              extras: extras,
              onSubmit: wrappedSubmit,
            );
        }
      },
    );
  }
}
