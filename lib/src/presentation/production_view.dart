import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/config_options.dart';
import '../models/inspect_mode.dart';
import '../models/production_strings.dart';
import '../models/report_payload.dart';
import 'developer_view.dart' show ScreenshotEditor, openScreenshotViewer;
import 'report_palette.dart';

/// Picker callback used by the gallery `+` button. When `null`, the button
/// is hidden. `ShakeContext` wires this to `image_picker`'s gallery flow.
typedef ImagePickerCallback = Future<Uint8List?> Function();

/// Privacy-first feedback sheet shown when [InspectMode.production] is
/// active.
///
/// Collects a plain-text description and an optional list of user-approved
/// images. The only auto-captured asset is [initialScreenshot] (or whatever
/// resolves out of [initialScreenshotFuture]); the user can remove it, tap
/// any tile to view it full-size, or open the screenshot editor to annotate
/// it before sending.
class ProductionView extends StatefulWidget {
  const ProductionView({
    super.key,
    required this.config,
    required this.onSubmit,
    this.metadata,
    this.initialScreenshot,
    this.initialScreenshotFuture,
    this.deviceInfoFuture,
    this.onPickImage,
    this.extras = const <String, Object?>{},
  });

  final ProductionConfig config;
  final ReportSubmittedCallback onSubmit;

  /// Host-provided context flowed through to the emitted [ReportPayload].
  final Map<String, Object?> extras;

  /// Diagnostic snapshot the engine kicked off before opening the sheet.
  /// In production this is intentionally thin — typically just the trigger
  /// timestamp, optionally device info when [ProductionConfig.captureDeviceInfo]
  /// is on. Logs, network, and route are never captured in production mode.
  /// When `null`, the view falls back to [ReportMetadata.empty].
  final ReportMetadata? metadata;

  /// Pre-resolved screenshot bytes attached on init. Can be removed by the
  /// user before submission.
  final Uint8List? initialScreenshot;

  /// In-flight screenshot capture. When the future resolves with bytes, they
  /// are appended to the attachment list (unless the user has dismissed the
  /// sheet or removed an existing attachment in the meantime).
  final Future<Uint8List?>? initialScreenshotFuture;

  /// In-flight device-info capture. Resolves into the diagnostics card and
  /// the submitted payload's `metadata.deviceInfo`.
  final Future<Map<String, Object?>>? deviceInfoFuture;

  /// Gallery picker. When `null`, the `+` button is hidden.
  final ImagePickerCallback? onPickImage;

  @override
  State<ProductionView> createState() => _ProductionViewState();
}

class _ProductionViewState extends State<ProductionView> {
  final TextEditingController _description = TextEditingController();
  final List<Uint8List> _images = [];
  bool _submitting = false;
  bool _autoScreenshotConsumed = false;
  late ReportMetadata _metadata = widget.metadata ?? ReportMetadata.empty();

  @override
  void initState() {
    super.initState();
    if (widget.config.allowScreenshotAttachment) {
      if (widget.initialScreenshot != null && _hasRoom) {
        _images.add(widget.initialScreenshot!);
        _autoScreenshotConsumed = true;
      }
      widget.initialScreenshotFuture?.then((bytes) {
        if (!mounted || bytes == null || _autoScreenshotConsumed) return;
        if (!_hasRoom) return;
        setState(() {
          _images.add(bytes);
          _autoScreenshotConsumed = true;
        });
      });
    }
    widget.deviceInfoFuture?.then((info) {
      if (!mounted) return;
      setState(() {
        _metadata = ReportMetadata(
          deviceInfo: info,
          timestamp: _metadata.timestamp,
        );
      });
    });
  }

  bool get _hasRoom => _images.length < widget.config.maxImages;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = widget.onPickImage;
    if (picker == null || !_hasRoom) return;
    final bytes = await picker();
    if (!mounted || bytes == null) return;
    if (!_hasRoom) return;
    setState(() => _images.add(bytes));
  }

  Future<void> _annotate(int index) async {
    final bytes = _images[index];
    final edited = await Navigator.of(context, rootNavigator: true)
        .push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScreenshotEditor(bytes: bytes),
      ),
    );
    if (!mounted || edited == null) return;
    setState(() => _images[index] = edited);
  }

  void _openViewer(int index) {
    openScreenshotViewer(
      context,
      _images[index],
      onEdit: _submitting ? null : () => _annotate(index),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final payload = ReportPayload(
      mode: InspectMode.production,
      userDescription: _description.text.trim(),
      images: List.of(_images),
      metadata: _metadata,
      extras: widget.extras,
    );
    try {
      await widget.onSubmit(payload);
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[shake_context] production onSubmit failed: $error\n$stack');
      }
      if (mounted) {
        // Keep the typed text + attachments intact so the user can retry —
        // never silently drop a report. The sheet stays open until they
        // dismiss it themselves.
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(widget.config.strings.submissionFailedMessage),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final palette = ReportPalette.resolve(context, widget.config.theme);
    final strings = widget.config.strings;
    final canPick =
        widget.onPickImage != null && widget.config.allowGalleryUpload;

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
                    palette: palette,
                    title: strings.title,
                    subtitle: strings.headerSubtitle,
                    dismissTooltip: strings.dismissTooltip,
                    onClose: _submitting
                        ? null
                        : () => Navigator.maybeOf(context)?.pop(),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(
                    text: strings.descriptionPrompt,
                    palette: palette,
                  ),
                  const SizedBox(height: 8),
                  _DescriptionField(
                    controller: _description,
                    hint: strings.hintText,
                    palette: palette,
                    enabled: !_submitting,
                  ),
                  const SizedBox(height: 20),
                  _AttachmentsSection(
                    images: _images,
                    palette: palette,
                    canPick: canPick,
                    maxImages: widget.config.maxImages,
                    submitting: _submitting,
                    strings: strings,
                    onPick: _pickImage,
                    onTap: _openViewer,
                    onAnnotate: (i) => _annotate(i),
                    onRemove: (i) => setState(() {
                      _images.removeAt(i);
                      _autoScreenshotConsumed = true;
                    }),
                  ),
                  const SizedBox(height: 20),
                  _DiagnosticsCard(
                    metadata: _metadata,
                    showDeviceInfo: widget.config.captureDeviceInfo,
                    palette: palette,
                    strings: strings,
                  ),
                  const SizedBox(height: 12),
                  _PrivacyNote(
                    text: strings.privacyNote,
                    palette: palette,
                  ),
                  const SizedBox(height: 24),
                  _ActionBar(
                    submitting: _submitting,
                    submitLabel: strings.submitLabel,
                    cancelLabel: strings.cancelLabel,
                    palette: palette,
                    onCancel: () => Navigator.maybeOf(context)?.pop(),
                    onSubmit: _submit,
                    textTheme: theme.textTheme,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.dismissTooltip,
    required this.onClose,
  });

  final ReportPalette palette;
  final String title;
  final String subtitle;
  final String dismissTooltip;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.chat_bubble_outline,
            color: palette.onPrimary,
            size: 20,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.subtitle,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.close, color: palette.subtitle),
          tooltip: dismissTooltip,
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.palette, this.trailing});

  final String text;
  final ReportPalette palette;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: palette.subtitle,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _DescriptionField extends StatelessWidget {
  const _DescriptionField({
    required this.controller,
    required this.hint,
    required this.palette,
    required this.enabled,
  });

  final TextEditingController controller;
  final String hint;
  final ReportPalette palette;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 4,
      maxLines: 8,
      enabled: enabled,
      style: TextStyle(color: palette.text, height: 1.4),
      cursorColor: palette.primary,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: palette.subtitle),
        filled: true,
        fillColor: palette.card,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _AttachmentsSection extends StatelessWidget {
  const _AttachmentsSection({
    required this.images,
    required this.palette,
    required this.canPick,
    required this.maxImages,
    required this.submitting,
    required this.strings,
    required this.onPick,
    required this.onTap,
    required this.onAnnotate,
    required this.onRemove,
  });

  final List<Uint8List> images;
  final ReportPalette palette;
  final bool canPick;
  final int maxImages;
  final bool submitting;
  final ProductionStrings strings;
  final VoidCallback onPick;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onAnnotate;
  final ValueChanged<int> onRemove;

  bool get _isFull => images.length >= maxImages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (images.isEmpty && !canPick) return const SizedBox.shrink();

    final showAdd = canPick && !_isFull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(
          text: '${strings.attachmentsLabel} (${images.length}/$maxImages)',
          palette: palette,
          trailing: showAdd
              ? TextButton.icon(
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: Text(strings.addImage),
                  onPressed: submitting ? null : onPick,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                )
              : (canPick && _isFull)
                  ? Text(
                      strings.limitReached,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: palette.subtitle,
                      ),
                    )
                  : null,
        ),
        const SizedBox(height: 10),
        if (images.isEmpty)
          _EmptyAttachments(
            palette: palette,
            canPick: canPick,
            strings: strings,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              // Two tiles per row on phones, three on wider sheets.
              final cols = constraints.maxWidth >= 520 ? 3 : 2;
              const spacing = 10.0;
              final tileSize =
                  (constraints.maxWidth - spacing * (cols - 1)) / cols;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (var i = 0; i < images.length; i++)
                    _AttachmentTile(
                      bytes: images[i],
                      size: tileSize,
                      palette: palette,
                      submitting: submitting,
                      strings: strings,
                      onTap: () => onTap(i),
                      onAnnotate: () => onAnnotate(i),
                      onRemove: () => onRemove(i),
                      isAuto: i == 0,
                      theme: theme,
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _EmptyAttachments extends StatelessWidget {
  const _EmptyAttachments({
    required this.palette,
    required this.canPick,
    required this.strings,
  });

  final ReportPalette palette;
  final bool canPick;
  final ProductionStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border, style: BorderStyle.solid),
      ),
      child: Row(
        children: [
          Icon(
            Icons.image_outlined,
            color: palette.subtitle,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              canPick ? strings.addAttachmentHint : strings.noAttachments,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.subtitle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.bytes,
    required this.size,
    required this.palette,
    required this.submitting,
    required this.strings,
    required this.onTap,
    required this.onAnnotate,
    required this.onRemove,
    required this.isAuto,
    required this.theme,
  });

  final Uint8List bytes;
  final double size;
  final ReportPalette palette;
  final bool submitting;
  final ProductionStrings strings;
  final VoidCallback onTap;
  final VoidCallback onAnnotate;
  final VoidCallback onRemove;
  final bool isAuto;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // Decode the screenshot at thumbnail resolution instead of the full
    // captured 3.0x pixel-ratio bitmap — a single full-res decode can hold
    // several MB in the image cache, multiplied by every visible tile.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = (size * dpr).round();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              color: palette.card,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: submitting ? null : onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      cacheWidth: decodeWidth,
                      errorBuilder: (_, _, _) => Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: palette.subtitle,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.45),
                            ],
                            stops: const [0.55, 1.0],
                          ),
                        ),
                      ),
                    ),
                    if (isAuto)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _Pill(
                          icon: Icons.auto_awesome,
                          label: strings.autoBadge,
                        ),
                      ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      right: 40,
                      child: _Pill(
                        icon: Icons.zoom_in,
                        label: strings.tapToView,
                      ),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: _CircleIconButton(
                        icon: Icons.edit_outlined,
                        tooltip: strings.annotateTooltip,
                        onTap: submitting ? null : onAnnotate,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -6,
            top: -6,
            child: Material(
              color: palette.background,
              shape: CircleBorder(side: BorderSide(color: palette.border)),
              child: Tooltip(
                message: strings.removeImageTooltip,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: submitting ? null : onRemove,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(Icons.close, size: 14, color: palette.text),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: Colors.white),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(7),
            child: Icon(Icons.edit_outlined, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Compact "sent with your report" disclosure shown above the privacy note.
///
/// Always shows the trigger time so support can prioritise by recency. When
/// [showDeviceInfo] is true, also shows a one-line digest of whatever device
/// info has resolved (model / OS / app version, depending on platform), and
/// exposes a "Show details" toggle that reveals every key/value being sent —
/// the user can verify the payload before submitting.
///
/// While the future is still in flight, the device row shows a discreet
/// "Resolving device info…" hint instead of jumping into view late.
class _DiagnosticsCard extends StatefulWidget {
  const _DiagnosticsCard({
    required this.metadata,
    required this.showDeviceInfo,
    required this.palette,
    required this.strings,
  });

  final ReportMetadata metadata;
  final bool showDeviceInfo;
  final ReportPalette palette;
  final ProductionStrings strings;

  @override
  State<_DiagnosticsCard> createState() => _DiagnosticsCardState();
}

class _DiagnosticsCardState extends State<_DiagnosticsCard> {
  bool _expanded = false;

  String _deviceSummary(Map<String, Object?> info) {
    // Prefer a friendly model + OS string when the standard device_info_plus
    // keys are present, but fall back to a generic comma-joined digest so
    // unknown platforms still surface something.
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = info[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final model = pick(['model', 'productName', 'deviceModel']);
    final os = pick([
      'systemName',
      'name', // linux distro
      'release',
      'kernelVersion',
    ]);
    final osVersion = pick([
      'systemVersion',
      'release',
      'osRelease',
      'displayVersion',
      'osVersion',
    ]);

    final parts = <String>[
      ?model,
      if (os != null && osVersion != null) '$os $osVersion' else ?osVersion,
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    return info.entries
        .take(3)
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = widget.palette;
    final metadata = widget.metadata;
    final strings = widget.strings;
    final hasDeviceInfo = metadata.deviceInfo.isNotEmpty;
    final canExpand = widget.showDeviceInfo && hasDeviceInfo;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: palette.primary),
              const SizedBox(width: 8),
              Text(
                strings.sentWithReport,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: palette.subtitle,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DiagRow(
            icon: Icons.schedule_outlined,
            label: strings.timeLabel,
            value: _formatProdTimestamp(metadata.timestamp),
            palette: palette,
            theme: theme,
          ),
          if (widget.showDeviceInfo) ...[
            const SizedBox(height: 6),
            _DiagRow(
              icon: Icons.phone_iphone_outlined,
              label: strings.deviceLabel,
              value: hasDeviceInfo
                  ? _deviceSummary(metadata.deviceInfo)
                  : strings.resolvingDeviceInfo,
              palette: palette,
              theme: theme,
              dim: !hasDeviceInfo,
            ),
          ],
          if (canExpand) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: palette.primary,
                ),
                label: Text(
                  _expanded ? strings.hideDetails : strings.showDetails,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: palette.primary,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 4),
              _DeviceInfoTable(
                info: metadata.deviceInfo,
                palette: palette,
                theme: theme,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Two-column key/value listing of every field in `metadata.deviceInfo`.
/// Shown when the user taps "Show details" so they can verify the exact
/// payload before submitting. Keys are sorted with `platform` pinned first
/// so the most identifying field anchors the list.
class _DeviceInfoTable extends StatelessWidget {
  const _DeviceInfoTable({
    required this.info,
    required this.palette,
    required this.theme,
  });

  final Map<String, Object?> info;
  final ReportPalette palette;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final keys = info.keys.toList()
      ..sort((a, b) {
        if (a == 'platform') return -1;
        if (b == 'platform') return 1;
        return a.compareTo(b);
      });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 108,
                  child: Text(
                    keys[i],
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.subtitle,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    '${info[keys[i]] ?? '—'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.text,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.palette,
    required this.theme,
    this.dim = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final ReportPalette palette;
  final ThemeData theme;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: palette.subtitle),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
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
            style: theme.textTheme.bodySmall?.copyWith(
              color: dim ? palette.subtitle : palette.text,
              fontStyle: dim ? FontStyle.italic : FontStyle.normal,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Human-readable local-time formatter mirroring the developer view's "Time"
/// row, so support staff see one consistent style across both modes.
/// Example: `Tuesday, May 19, 2026 · 4:32 PM`.
String _formatProdTimestamp(DateTime t) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
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
  final local = t.toLocal();
  final weekday = weekdays[local.weekday - 1];
  final month = months[local.month - 1];
  var hour = local.hour % 12;
  if (hour == 0) hour = 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$weekday, $month ${local.day}, ${local.year} · $hour:$minute $period';
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.text, required this.palette});

  final String text;
  final ReportPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 18, color: palette.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.subtitle,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.submitting,
    required this.submitLabel,
    required this.cancelLabel,
    required this.palette,
    required this.onCancel,
    required this.onSubmit,
    required this.textTheme,
  });

  final bool submitting;
  final String submitLabel;
  final String cancelLabel;
  final ReportPalette palette;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.cancelForeground,
              side: BorderSide(color: palette.cancelForeground),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: submitting ? null : onCancel,
            child: Text(cancelLabel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: palette.submitBackground,
              foregroundColor: palette.submitForeground,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: submitting ? null : onSubmit,
            icon: submitting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.submitForeground,
                    ),
                  )
                : const Icon(Icons.send_outlined, size: 18),
            label: Text(
              submitLabel,
              style: textTheme.titleMedium?.copyWith(
                color: palette.submitForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
