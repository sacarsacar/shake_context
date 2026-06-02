import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/config_options.dart';
import '../models/inspect_mode.dart';
import '../models/log_entry.dart';
import '../models/network_log.dart';
import '../models/report_payload.dart';
import 'report_palette.dart';

/// Diagnostic dashboard shown when [InspectMode.developer] is active.
///
/// Surfaces everything the engineer needs in a single sheet: current route,
/// device snapshot, recent console logs, and an annotatable screenshot
/// thumbnail. Submitting fires [onSubmit] with a developer [ReportPayload]
/// containing all available diagnostics plus an optional note.
///
/// The screenshot bytes and device info can each be supplied either eagerly
/// via [screenshot] / [metadata], or asynchronously via
/// [screenshotFuture] / [deviceInfoFuture]. When the futures resolve the
/// view rebuilds with the new values.
class DeveloperView extends StatefulWidget {
  const DeveloperView({
    super.key,
    required this.config,
    required this.metadata,
    required this.onSubmit,
    this.screenshot,
    this.screenshotFuture,
    this.deviceInfoFuture,
    this.extras = const <String, Object?>{},
  });

  final DeveloperConfig config;
  final ReportMetadata metadata;
  final ReportSubmittedCallback onSubmit;

  final Uint8List? screenshot;
  final Future<Uint8List?>? screenshotFuture;
  final Future<Map<String, Object?>>? deviceInfoFuture;

  /// Host-provided context flowed through to the emitted [ReportPayload].
  final Map<String, Object?> extras;

  @override
  State<DeveloperView> createState() => _DeveloperViewState();
}

class _DeveloperViewState extends State<DeveloperView> {
  final TextEditingController _note = TextEditingController();
  bool _submitting = false;
  late Uint8List? _screenshot = widget.screenshot;
  late ReportMetadata _metadata = widget.metadata;

  @override
  void initState() {
    super.initState();
    widget.screenshotFuture?.then((bytes) {
      if (!mounted || bytes == null) return;
      setState(() => _screenshot = bytes);
    });
    widget.deviceInfoFuture?.then((info) {
      if (!mounted) return;
      setState(() {
        _metadata = ReportMetadata(
          currentRoute: _metadata.currentRoute,
          deviceInfo: info,
          logs: _metadata.logs,
          networkLogs: _metadata.networkLogs,
          previousSessionLogs: _metadata.previousSessionLogs,
          previousSessionNetwork: _metadata.previousSessionNetwork,
          previousSessionStartedAt: _metadata.previousSessionStartedAt,
          timestamp: _metadata.timestamp,
        );
      });
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final payload = ReportPayload(
      mode: InspectMode.developer,
      userDescription: _note.text.trim(),
      images: _screenshot != null ? [_screenshot!] : const [],
      metadata: _metadata,
      extras: widget.extras,
    );
    try {
      await widget.onSubmit(payload);
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[shake_context] developer onSubmit failed: $error\n$stack');
      }
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text("Couldn't send report: $error"),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _previousSessionTitle(String prefix, DateTime? startedAt) {
    if (startedAt == null) return prefix;
    return '$prefix · ${_formatTimestamp(startedAt, includeSeconds: false)}';
  }

  Future<void> _openEditor() async {
    final bytes = _screenshot;
    if (bytes == null) return;
    final edited = await Navigator.of(context, rootNavigator: true).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScreenshotEditor(bytes: bytes),
      ),
    );
    if (!mounted || edited == null) return;
    setState(() => _screenshot = edited);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final meta = _metadata;
    final palette = ReportPalette.resolve(context, widget.config.theme);

    final wide = media.size.width >= 600;
    final shotHeight = wide ? 360.0 : 260.0;
    final logHeight = wide ? 140.0 : 110.0;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + media.viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    icon: Icons.build_circle_outlined,
                    title: 'Developer Report',
                    palette: palette,
                    onClose: _submitting
                        ? null
                        : () => Navigator.maybeOf(context)?.pop(),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: 'Diagnostics',
                    icon: Icons.fact_check_outlined,
                    palette: palette,
                    child: Column(
                      children: [
                        if (widget.config.captureRoute)
                          _DiagnosticRow(
                            label: 'Route',
                            value: meta.currentRoute ?? '(unknown)',
                            palette: palette,
                          ),
                        if (widget.config.captureDeviceInfo)
                          _DiagnosticRow(
                            label: 'Device',
                            value: _formatDeviceInfo(meta.deviceInfo),
                            palette: palette,
                          ),
                        _DiagnosticRow(
                          label: 'Time',
                          value: _formatTimestamp(meta.timestamp),
                          palette: palette,
                        ),
                      ],
                    ),
                  ),
                  if (widget.config.captureScreenshot) ...[
                    const SizedBox(height: 12),
                    _Section(
                      title: 'Screenshot',
                      icon: Icons.image_outlined,
                      palette: palette,
                      trailing: _screenshot == null
                          ? null
                          : TextButton.icon(
                              onPressed: _openEditor,
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Annotate'),
                              style: TextButton.styleFrom(
                                foregroundColor: palette.primary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                      child: _ScreenshotPreview(
                        bytes: _screenshot,
                        height: shotHeight,
                        palette: palette,
                        onEdit: _screenshot == null ? null : _openEditor,
                      ),
                    ),
                  ],
                  if (widget.config.captureConsoleLogs) ...[
                    const SizedBox(height: 12),
                    _Section(
                      title: 'Recent logs',
                      icon: Icons.terminal,
                      palette: palette,
                      child: _LogPanel(
                        entries: meta.logs,
                        height: logHeight,
                        palette: palette,
                      ),
                    ),
                  ],
                  if (widget.config.captureNetworkLogs &&
                      meta.networkLogs.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _Section(
                      title: 'Network',
                      icon: Icons.cloud_outlined,
                      palette: palette,
                      child: _NetworkPanel(
                        entries: meta.networkLogs,
                        height: logHeight,
                        palette: palette,
                      ),
                    ),
                  ],
                  if (meta.previousSessionLogs.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _Section(
                      title: _previousSessionTitle(
                          'Previous session — logs',
                          meta.previousSessionStartedAt),
                      icon: Icons.history,
                      palette: palette,
                      child: _LogPanel(
                        entries: meta.previousSessionLogs,
                        height: logHeight,
                        palette: palette,
                      ),
                    ),
                  ],
                  if (meta.previousSessionNetwork.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _Section(
                      title: _previousSessionTitle(
                          'Previous session — network',
                          meta.previousSessionStartedAt),
                      icon: Icons.history,
                      palette: palette,
                      child: _NetworkPanel(
                        entries: meta.previousSessionNetwork,
                        height: logHeight,
                        palette: palette,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _note,
                    minLines: 2,
                    maxLines: 4,
                    enabled: !_submitting,
                    style: TextStyle(color: palette.text),
                    cursorColor: palette.primary,
                    decoration: InputDecoration(
                      labelText: 'Optional note',
                      labelStyle: TextStyle(color: palette.subtitle),
                      floatingLabelStyle: TextStyle(color: palette.primary),
                      filled: true,
                      fillColor: palette.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: palette.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ActionBar(
                    submitting: _submitting,
                    palette: palette,
                    onCancel: () => Navigator.maybeOf(context)?.pop(),
                    onSubmit: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDeviceInfo(Map<String, Object?> info) {
    if (info.isEmpty) return '(unavailable)';
    return info.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.palette,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final ReportPalette palette;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: palette.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: palette.onPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.close, color: palette.subtitle),
          tooltip: 'Dismiss',
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.palette,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final ReportPalette palette;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: palette.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: palette.subtitle,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.submitting,
    required this.palette,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool submitting;
  final ReportPalette palette;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.cancelForeground,
              side: BorderSide(color: palette.cancelForeground),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: submitting ? null : onCancel,
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: palette.submitBackground,
              foregroundColor: palette.submitForeground,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: submitting ? null : onSubmit,
            icon: submitting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.submitForeground,
                    ),
                  )
                : const Icon(Icons.send),
            label: const Text('Send'),
          ),
        ),
      ],
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final String value;
  final ReportPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.subtitle,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotPreview extends StatelessWidget {
  const _ScreenshotPreview({
    required this.bytes,
    required this.height,
    required this.palette,
    required this.onEdit,
  });

  final Uint8List? bytes;
  final double height;
  final ReportPalette palette;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: palette.card,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: bytes == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.image_not_supported_outlined,
                      color: palette.subtitle,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'No screenshot captured',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.subtitle,
                      ),
                    ),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.memory(
                      bytes!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: palette.subtitle,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _PillBadge(
                      icon: Icons.zoom_in,
                      label: 'Tap to view',
                    ),
                  ),
                ],
              ),
      ),
    );

    if (bytes == null) return preview;

    return Semantics(
      button: true,
      label: 'View screenshot full-size',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openViewer(context, bytes!, onEdit),
        child: preview,
      ),
    );
  }

  void _openViewer(BuildContext context, Uint8List shot, VoidCallback? onEdit) {
    openScreenshotViewer(context, shot, onEdit: onEdit);
  }
}

/// Push a fullscreen [ScreenshotViewer] route on the root navigator.
///
/// Shared between the developer and production report surfaces so both
/// flows present the same tap-to-zoom + Annotate experience.
void openScreenshotViewer(
  BuildContext context,
  Uint8List bytes, {
  VoidCallback? onEdit,
}) {
  final scrim = Theme.of(context).colorScheme.scrim.withValues(alpha: 0.92);
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: scrim,
      pageBuilder: (_, _, _) =>
          ScreenshotViewer(bytes: bytes, onEdit: onEdit),
    ),
  );
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fullscreen, pinch-zoomable preview of a captured screenshot.
///
/// Pushed by [openScreenshotViewer]. Tapping the backdrop dismisses; if an
/// [onEdit] callback is supplied, an "Annotate" pill appears in the top-right
/// and forwards control to the screenshot editor on tap.
class ScreenshotViewer extends StatelessWidget {
  const ScreenshotViewer({
    super.key,
    required this.bytes,
    required this.onEdit,
  });

  final Uint8List bytes;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  if (onEdit != null)
                    Material(
                      color: Colors.black54,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () {
                          Navigator.of(context).pop();
                          onEdit!();
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_outlined,
                                  size: 16, color: Colors.white),
                              SizedBox(width: 6),
                              Text('Annotate',
                                  style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _colorForLevel(LogLevel level, ThemeData theme, ReportPalette palette) {
  switch (level) {
    case LogLevel.error:
      return theme.colorScheme.error;
    case LogLevel.warning:
      return const Color(0xFFB8860B);
    case LogLevel.info:
      return palette.text;
    case LogLevel.debug:
      return palette.subtitle;
  }
}

String _formatRelative(DateTime t, DateTime origin) {
  final ms = t.difference(origin).inMilliseconds;
  if (ms < 1000) return '+${ms}ms';
  final s = ms / 1000;
  if (s < 60) return '+${s.toStringAsFixed(s < 10 ? 1 : 0)}s';
  final m = (s / 60).floor();
  final remS = (s - m * 60).toStringAsFixed(0);
  return '+${m}m${remS}s';
}

const List<String> _kWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _kMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Human-readable timestamp used across the developer report surface.
///
/// Renders the local-time wall clock the engineer is looking at, not UTC,
/// so the value matches what they'd read off their phone. Example output:
/// `Tuesday, May 19, 2026 · 4:32:18 PM`. Pass [includeSeconds]: false for
/// a more compact subtitle form (`Tue, May 19, 2026 · 4:32 PM`).
String _formatTimestamp(DateTime t, {bool includeSeconds = true}) {
  final local = t.toLocal();
  final weekday = _kWeekdays[local.weekday - 1];
  final month = _kMonths[local.month - 1];
  final day = local.day;
  final year = local.year;

  var hour = local.hour % 12;
  if (hour == 0) hour = 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';

  final time = includeSeconds
      ? '$hour:$minute:${local.second.toString().padLeft(2, '0')} $period'
      : '$hour:$minute $period';

  final weekdayLabel =
      includeSeconds ? weekday : weekday.substring(0, 3);
  final monthLabel = includeSeconds ? month : month.substring(0, 3);

  return '$weekdayLabel, $monthLabel $day, $year · $time';
}

class _LogPanel extends StatefulWidget {
  const _LogPanel({
    required this.entries,
    required this.height,
    required this.palette,
  });

  final List<LogEntry> entries;
  final double height;
  final ReportPalette palette;

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  final Set<LogLevel> _activeLevels = {...LogLevel.values};
  String _query = '';
  // Explicit controller shared with the Scrollbar. Without it, the Scrollbar
  // falls back to PrimaryScrollController, which Flutter does not auto-attach
  // to vertical ListViews on desktop — producing a "ScrollController has no
  // ScrollPosition attached" exception on the first scroll gesture.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<LogEntry> get _filtered {
    final q = _query.trim().toLowerCase();
    return widget.entries.where((e) {
      if (!_activeLevels.contains(e.level)) return false;
      if (q.isEmpty) return true;
      return e.message.toLowerCase().contains(q) ||
          (e.source?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = widget.palette;
    final entries = _filtered;
    final origin = widget.entries.isEmpty
        ? DateTime.now()
        : widget.entries.first.timestamp;

    return Container(
      height: widget.height + 88,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterChipRow(
            options: [
              for (final level in LogLevel.values)
                _ChipOption(
                  label: level.name,
                  selected: _activeLevels.contains(level),
                  onChanged: (v) => setState(() {
                    if (v) {
                      _activeLevels.add(level);
                    } else {
                      _activeLevels.remove(level);
                    }
                  }),
                ),
            ],
            palette: palette,
          ),
          const SizedBox(height: 6),
          _SearchField(
            palette: palette,
            hint: 'Search logs…',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      widget.entries.isEmpty
                          ? 'No logs captured'
                          : 'No logs match the filter',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.subtitle,
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _scrollController,
                    child: ListView.separated(
                      controller: _scrollController,
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (_, i) {
                        final e = entries[i];
                        return _LogRow(
                          entry: e,
                          origin: origin,
                          palette: palette,
                          onTap: () => _openDetails(context, e),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _openDetails(BuildContext context, LogEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LogDetailsSheet(entry: entry, palette: widget.palette),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.entry,
    required this.origin,
    required this.palette,
    required this.onTap,
  });

  final LogEntry entry;
  final DateTime origin;
  final ReportPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorForLevel(entry.level, theme, palette);
    final ts = _formatRelative(entry.timestamp, origin);
    final src = entry.source != null ? '[${entry.source}] ' : '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Text(
          '$ts $src${entry.message}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: color,
            fontWeight: entry.level == LogLevel.error
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _LogDetailsSheet extends StatelessWidget {
  const _LogDetailsSheet({required this.entry, required this.palette});

  final LogEntry entry;
  final ReportPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullText = StringBuffer()
      ..writeln('${entry.timestamp.toIso8601String()} '
          '[${entry.level.name.toUpperCase()}]'
          '${entry.source != null ? ' (${entry.source})' : ''}')
      ..writeln(entry.message);
    if (entry.stackTrace != null) {
      fullText.writeln();
      fullText.writeln(entry.stackTrace);
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Log entry · ${entry.level.name}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fullText.toString()));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  fullText.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: palette.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkPanel extends StatefulWidget {
  const _NetworkPanel({
    required this.entries,
    required this.height,
    required this.palette,
  });

  final List<NetworkLog> entries;
  final double height;
  final ReportPalette palette;

  @override
  State<_NetworkPanel> createState() => _NetworkPanelState();
}

enum _NetFilter { all, failed, slow }

class _NetworkPanelState extends State<_NetworkPanel> {
  _NetFilter _filter = _NetFilter.all;
  String _query = '';
  // See _LogPanelState — Scrollbar/ListView need a shared controller on
  // desktop to satisfy the framework's hover-fade animation.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static const int _slowMs = 1000;

  List<NetworkLog> get _filtered {
    final q = _query.trim().toLowerCase();
    return widget.entries.where((e) {
      switch (_filter) {
        case _NetFilter.failed:
          if (!e.isFailure) return false;
          break;
        case _NetFilter.slow:
          if ((e.durationMs ?? 0) < _slowMs) return false;
          break;
        case _NetFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      return e.url.toLowerCase().contains(q) ||
          e.method.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = widget.palette;
    final entries = _filtered;

    return Container(
      height: widget.height + 88,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterChipRow(
            options: [
              for (final f in _NetFilter.values)
                _ChipOption(
                  label: f.name,
                  selected: _filter == f,
                  onChanged: (v) {
                    if (v) setState(() => _filter = f);
                  },
                ),
            ],
            palette: palette,
          ),
          const SizedBox(height: 6),
          _SearchField(
            palette: palette,
            hint: 'Search URL / method…',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      widget.entries.isEmpty
                          ? 'No requests captured'
                          : 'No requests match the filter',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.subtitle,
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _scrollController,
                    child: ListView.separated(
                      controller: _scrollController,
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (_, i) {
                        final e = entries[i];
                        return _NetworkRow(
                          entry: e,
                          palette: palette,
                          onTap: () => _openDetails(context, e),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _openDetails(BuildContext context, NetworkLog entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _NetworkDetailsSheet(entry: entry, palette: widget.palette),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.entry,
    required this.palette,
    required this.onTap,
  });

  final NetworkLog entry;
  final ReportPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status =
        entry.error != null ? 'ERR' : entry.statusCode?.toString() ?? '…';
    final color = entry.isFailure ? theme.colorScheme.error : palette.text;
    final duration =
        entry.durationMs != null ? ' · ${entry.durationMs}ms' : '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Text(
          '$status ${entry.method.toUpperCase()} ${entry.url}$duration'
          '${entry.error != null ? '\n  ${entry.error}' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: color,
            fontWeight: entry.isFailure ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _NetworkDetailsSheet extends StatelessWidget {
  const _NetworkDetailsSheet({required this.entry, required this.palette});

  final NetworkLog entry;
  final ReportPalette palette;

  String _format() {
    final buf = StringBuffer()
      ..writeln(
          '${entry.method.toUpperCase()} ${entry.url}')
      ..writeln('Status: ${entry.statusCode ?? '—'}'
          '${entry.durationMs != null ? ' · ${entry.durationMs}ms' : ''}'
          '${entry.error != null ? ' · ERROR: ${entry.error}' : ''}')
      ..writeln('Time: ${_formatTimestamp(entry.timestamp)}');
    if (entry.requestHeaders != null && entry.requestHeaders!.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Request headers:');
      entry.requestHeaders!.forEach((k, v) => buf.writeln('  $k: $v'));
    }
    if (entry.requestBody != null && entry.requestBody!.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Request body:')
        ..writeln(entry.requestBody);
    }
    if (entry.responseHeaders != null && entry.responseHeaders!.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Response headers:');
      entry.responseHeaders!.forEach((k, v) => buf.writeln('  $k: $v'));
    }
    if (entry.responseBody != null && entry.responseBody!.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Response body:')
        ..writeln(entry.responseBody);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _format();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Request · ${entry.method.toUpperCase()}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: palette.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipOption {
  _ChipOption({
    required this.label,
    required this.selected,
    required this.onChanged,
  });
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;
}

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({required this.options, required this.palette});

  final List<_ChipOption> options;
  final ReportPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final o = options[i];
          return FilterChip(
            label: Text(o.label),
            selected: o.selected,
            onSelected: o.onChanged,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: palette.card,
            selectedColor: palette.primary.withValues(alpha: 0.15),
            side: BorderSide(color: palette.border),
            labelStyle: TextStyle(
              fontSize: 12,
              color: o.selected ? palette.primary : palette.text,
              fontWeight: o.selected ? FontWeight.w600 : FontWeight.normal,
            ),
          );
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.palette,
    required this.hint,
    required this.onChanged,
  });

  final ReportPalette palette;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextField(
        onChanged: onChanged,
        style: TextStyle(fontSize: 12, color: palette.text),
        cursorColor: palette.primary,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: palette.subtitle, fontSize: 12),
          prefixIcon: Icon(Icons.search, size: 16, color: palette.subtitle),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 28, minHeight: 28),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: palette.primary, width: 1.2),
          ),
        ),
      ),
    );
  }
}

/// Full-screen annotation editor for a captured screenshot.
///
/// Lets the developer draw freehand strokes and drop text labels on top of
/// the screenshot. Returns a flattened PNG (via [RenderRepaintBoundary]) on
/// save, or `null` on cancel.
///
/// Package-internal because it lives under `lib/src/` and is not re-exported
/// from the public `shake_context.dart` barrel. Shared by the developer and
/// production report surfaces, and used directly by widget tests.
class ScreenshotEditor extends StatefulWidget {
  const ScreenshotEditor({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<ScreenshotEditor> createState() => _ScreenshotEditorState();
}

class _Stroke {
  _Stroke({required this.color, required this.width, required this.points});
  final Color color;
  final double width;
  final List<Offset> points;
}

class _ScreenshotEditorState extends State<ScreenshotEditor> {
  final GlobalKey _captureKey = GlobalKey();

  final List<_Stroke> _strokes = [];
  _Stroke? _current;

  Color _color = Colors.red;
  double _stroke = 4;
  bool _exporting = false;

  Future<ui.Image>? _decoded;

  static const List<Color> _palette = [
    Colors.red,
    Colors.orange,
    Colors.green,
    Colors.blue,
    Colors.black,
    Colors.white,
  ];

  @override
  void initState() {
    super.initState();
    _decoded = _decode(widget.bytes);
  }

  @override
  void dispose() {
    // Release the decoded GPU-side image. Without this, the `ui.Image`
    // held by `_decoded` lingers until GC catches up — which on a heavily
    // annotated screenshot can mean tens of MB pinned per editor session.
    _decoded?.then((image) => image.dispose()).catchError((Object _) {
      // Decode itself failed — nothing to release.
    });
    super.dispose();
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _current = null;
    });
  }

  Future<void> _save() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final boundary = _captureKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image =
          await boundary.toImage(pixelRatio: View.of(context).devicePixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        if (mounted) {
          _showSaveError("Couldn't encode the annotated screenshot.");
        }
        return;
      }
      final out = byteData.buffer.asUint8List();
      if (mounted) Navigator.of(context).pop(out);
    } catch (error, stack) {
      // Re-rasterising can fail when the boundary has been detached
      // mid-export (e.g. system back gesture). Surface the failure so the
      // user isn't left with a perpetually-disabled save button and no
      // explanation.
      if (kDebugMode) {
        debugPrint('[shake_context] ScreenshotEditor._save failed: $error\n$stack');
      }
      if (mounted) {
        _showSaveError("Couldn't save your annotation — please try again.");
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showSaveError(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: _exporting ? null : () => Navigator.of(context).pop(),
        ),
        title: const Text('Annotate'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
            onPressed: _strokes.isEmpty || _exporting ? null : _undo,
          ),
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _strokes.isEmpty || _exporting ? null : _clear,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton.icon(
              onPressed: _exporting ? null : _save,
              icon: _exporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.all(12),
              child: Center(
                child: FutureBuilder<ui.Image>(
                  future: _decoded,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done ||
                        snap.data == null) {
                      return const CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white70),
                      );
                    }
                    final img = snap.data!;
                    final aspect = img.width / img.height;
                    return AspectRatio(
                      aspectRatio: aspect,
                      child: RepaintBoundary(
                        key: _captureKey,
                        child: ClipRect(
                          child: _AnnotationCanvas(
                            bytes: widget.bytes,
                            strokes: _strokes,
                            current: _current,
                            onPanStart: (offset) {
                              setState(() {
                                _current = _Stroke(
                                  color: _color,
                                  width: _stroke,
                                  points: [offset],
                                );
                              });
                            },
                            onPanUpdate: (offset) {
                              if (_current == null) return;
                              setState(() => _current!.points.add(offset));
                            },
                            onPanEnd: () {
                              if (_current == null) return;
                              setState(() {
                                _strokes.add(_current!);
                                _current = null;
                              });
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          _Toolbar(
            color: _color,
            stroke: _stroke,
            palette: _palette,
            onColorChanged: (c) => setState(() => _color = c),
            onStrokeChanged: (w) => setState(() => _stroke = w),
            disabled: _exporting,
          ),
        ],
      ),
    );
  }
}

class _AnnotationCanvas extends StatelessWidget {
  const _AnnotationCanvas({
    required this.bytes,
    required this.strokes,
    required this.current,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final Uint8List bytes;
  final List<_Stroke> strokes;
  final _Stroke? current;
  final ValueChanged<Offset> onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          bytes,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _StrokesPainter(
              strokes: strokes,
              current: current,
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (d) => onPanStart(d.localPosition),
            onPanUpdate: (d) => onPanUpdate(d.localPosition),
            onPanEnd: (_) => onPanEnd(),
          ),
        ),
      ],
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter({required this.strokes, required this.current});

  final List<_Stroke> strokes;
  final _Stroke? current;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _paintStroke(canvas, s);
    }
    final c = current;
    if (c != null) _paintStroke(canvas, c);
  }

  void _paintStroke(Canvas canvas, _Stroke s) {
    final paint = Paint()
      ..color = s.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s.width
      ..style = PaintingStyle.stroke;
    if (s.points.length == 1) {
      canvas.drawCircle(s.points.first, s.width / 2, Paint()..color = s.color);
      return;
    }
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (var i = 1; i < s.points.length; i++) {
      path.lineTo(s.points[i].dx, s.points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StrokesPainter old) => true;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.color,
    required this.stroke,
    required this.palette,
    required this.onColorChanged,
    required this.onStrokeChanged,
    required this.disabled,
  });

  final Color color;
  final double stroke;
  final List<Color> palette;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeChanged;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.brush_outlined,
                    size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                const Text(
                  'Stroke',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: stroke,
                    min: 2,
                    max: 16,
                    onChanged: disabled ? null : onStrokeChanged,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final c in palette)
                  GestureDetector(
                    onTap: disabled ? null : () => onColorChanged(c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == color ? Colors.white : Colors.white24,
                          width: c == color ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Drag on the screenshot to draw',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
