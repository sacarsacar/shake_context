import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'inspect_mode.dart';
import 'log_entry.dart';
import 'network_log.dart';

/// Auxiliary diagnostic snapshot attached to a [ReportPayload].
///
/// In [InspectMode.production] this object is intentionally near-empty —
/// the user has not consented to telemetry collection. In
/// [InspectMode.developer] the fields are populated by the capture pipeline.
@immutable
class ReportMetadata {
  ReportMetadata({
    this.currentRoute,
    Map<String, Object?>? deviceInfo,
    List<LogEntry>? logs,
    List<NetworkLog>? networkLogs,
    List<LogEntry>? previousSessionLogs,
    List<NetworkLog>? previousSessionNetwork,
    this.previousSessionStartedAt,
    DateTime? timestamp,
  })  : deviceInfo = Map.unmodifiable(deviceInfo ?? const <String, Object?>{}),
        logs = List.unmodifiable(logs ?? const <LogEntry>[]),
        networkLogs = List.unmodifiable(networkLogs ?? const <NetworkLog>[]),
        previousSessionLogs =
            List.unmodifiable(previousSessionLogs ?? const <LogEntry>[]),
        previousSessionNetwork = List.unmodifiable(
            previousSessionNetwork ?? const <NetworkLog>[]),
        timestamp = timestamp ?? DateTime.now();

  /// Empty metadata shape — the default for production payloads.
  factory ReportMetadata.empty() => ReportMetadata();

  /// Active route name at the moment shake fired, when discoverable.
  final String? currentRoute;

  /// Device hardware / OS snapshot. Keys are intentionally untyped to keep
  /// the model decoupled from `device_info_plus` response shapes.
  final Map<String, Object?> deviceInfo;

  /// Rolling buffer of captured log entries — `print`, `debugPrint`,
  /// uncaught Flutter and async errors, and anything pushed via
  /// `ShakeContext.log(...)`. See [LogEntry] for the per-row shape.
  final List<LogEntry> logs;

  /// Rolling buffer of captured HTTP request/response cycles, populated by
  /// `ShakeDioInterceptor` or a host-provided adapter.
  final List<NetworkLog> networkLogs;

  /// Log entries recovered from the previous app session via the
  /// `persistLogs` flag on `ShakeContext.guard`. Empty when persistence is
  /// off or the prior session exited cleanly.
  final List<LogEntry> previousSessionLogs;

  /// Network entries recovered from the previous session. Same lifecycle
  /// rules as [previousSessionLogs].
  final List<NetworkLog> previousSessionNetwork;

  /// When the previous session started, surfaced so the overlay can tell
  /// the engineer how stale the recovered data is. Null when there is no
  /// recovered session.
  final DateTime? previousSessionStartedAt;

  /// When the shake fired.
  final DateTime timestamp;

  /// JSON-serializable representation. Timestamps are ISO 8601 strings;
  /// nested logs and network entries are flattened via their own
  /// `toJson()`. Optional scalar fields (route, previous-session start) are
  /// omitted when null; collections are always present (possibly empty) so
  /// backends see a predictable schema.
  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        if (currentRoute != null) 'currentRoute': currentRoute,
        'deviceInfo': deviceInfo,
        'logs': logs.map((e) => e.toJson()).toList(),
        'networkLogs': networkLogs.map((e) => e.toJson()).toList(),
        'previousSessionLogs':
            previousSessionLogs.map((e) => e.toJson()).toList(),
        'previousSessionNetwork':
            previousSessionNetwork.map((e) => e.toJson()).toList(),
        if (previousSessionStartedAt != null)
          'previousSessionStartedAt':
              previousSessionStartedAt!.toIso8601String(),
      };

  /// Inverse of [toJson]. Defensive — missing or wrong-typed fields fall
  /// back to safe defaults so a partly-corrupt queue file never throws.
  factory ReportMetadata.fromJson(Map<String, dynamic> json) {
    List<LogEntry> parseLogs(dynamic raw) {
      if (raw is! List) return const <LogEntry>[];
      final out = <LogEntry>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          try {
            out.add(LogEntry.fromJson(item));
          } catch (_) {/* skip individually broken entries */}
        }
      }
      return out;
    }

    List<NetworkLog> parseNetwork(dynamic raw) {
      if (raw is! List) return const <NetworkLog>[];
      final out = <NetworkLog>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          try {
            out.add(NetworkLog.fromJson(item));
          } catch (_) {/* skip */}
        }
      }
      return out;
    }

    Map<String, Object?>? parseStringKeyedMap(dynamic raw) {
      if (raw is! Map) return null;
      return <String, Object?>{
        for (final entry in raw.entries) entry.key.toString(): entry.value,
      };
    }

    return ReportMetadata(
      currentRoute:
          json['currentRoute'] is String ? json['currentRoute'] as String : null,
      deviceInfo: parseStringKeyedMap(json['deviceInfo']),
      logs: parseLogs(json['logs']),
      networkLogs: parseNetwork(json['networkLogs']),
      previousSessionLogs: parseLogs(json['previousSessionLogs']),
      previousSessionNetwork: parseNetwork(json['previousSessionNetwork']),
      previousSessionStartedAt: json['previousSessionStartedAt'] is String
          ? DateTime.tryParse(json['previousSessionStartedAt'] as String)
          : null,
      timestamp: json['timestamp'] is String
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReportMetadata &&
        other.currentRoute == currentRoute &&
        mapEquals(other.deviceInfo, deviceInfo) &&
        listEquals(other.logs, logs) &&
        listEquals(other.networkLogs, networkLogs) &&
        listEquals(other.previousSessionLogs, previousSessionLogs) &&
        listEquals(other.previousSessionNetwork, previousSessionNetwork) &&
        other.previousSessionStartedAt == previousSessionStartedAt &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(
        currentRoute,
        Object.hashAllUnordered(deviceInfo.entries.map((e) => e.key)),
        Object.hashAll(logs),
        Object.hashAll(networkLogs),
        Object.hashAll(previousSessionLogs),
        Object.hashAll(previousSessionNetwork),
        previousSessionStartedAt,
        timestamp,
      );
}

/// The unified object emitted by [ShakeContext.onReportSubmitted].
///
/// Both modes produce the same shape so callers can route to different
/// pipelines based on [mode] without two callbacks.
@immutable
class ReportPayload {
  ReportPayload({
    required this.mode,
    required this.userDescription,
    List<Uint8List>? images,
    ReportMetadata? metadata,
    Map<String, Object?>? extras,
  })  : images = List.unmodifiable(images ?? const <Uint8List>[]),
        metadata = metadata ?? ReportMetadata.empty(),
        extras = Map.unmodifiable(extras ?? const <String, Object?>{});

  /// Mode the payload originated from. Lets the consumer dispatch to a
  /// support channel vs. a DevOps channel.
  final InspectMode mode;

  /// Plain text written by the user. In developer mode this may be empty
  /// when the engineer just wants telemetry.
  final String userDescription;

  /// Attached image bytes. In production this is whatever the user kept or
  /// added. In developer this typically holds the auto-captured screenshot.
  final List<Uint8List> images;

  /// Diagnostic snapshot. Near-empty in production, populated in developer.
  final ReportMetadata metadata;

  /// Host-provided context that doesn't belong in [metadata] (which is
  /// reserved for what the package captures itself).
  ///
  /// Use it to attach identifiers and stage info the package can't know:
  /// `installationId`, `userId`, `releaseChannel`, `flavor`, feature-flag
  /// state, etc. Values must be JSON-encodable for [toJson] to round-trip
  /// cleanly. Empty when the host didn't pass `extras` to [ShakeContext].
  ///
  /// Set once via `ShakeContext(extras: { … })` — the same map flows into
  /// every payload from that engine.
  final Map<String, Object?> extras;

  /// First attached image, or `null` when none were captured. Convenience
  /// for the developer-mode case where exactly one auto-screenshot is
  /// expected, or for production hosts that only want the primary image.
  Uint8List? get primaryImage => images.isEmpty ? null : images.first;

  /// JSON-serializable representation.
  ///
  /// By default `images` is **excluded** and only `imageCount` is emitted —
  /// the binary path is to upload `payload.images` separately as multipart
  /// (smaller wire size, faster, what most backends expect). When you need
  /// a fully self-contained JSON blob (e.g. a single webhook POST), pass
  /// `includeImages: true` to base64-encode each image inline.
  Map<String, dynamic> toJson({bool includeImages = false}) => {
        'mode': mode.name,
        'userDescription': userDescription,
        'imageCount': images.length,
        if (includeImages)
          'images': images.map(base64Encode).toList(),
        if (extras.isNotEmpty) 'extras': extras,
        'metadata': metadata.toJson(),
      };

  /// Inverse of [toJson]. Tolerates `includeImages: false` payloads (parses
  /// to an empty image list) and `includeImages: true` payloads
  /// (base64-decodes back to bytes).
  ///
  /// Defensive: unknown `mode` values fall back to
  /// [InspectMode.production] — that's the safer default for an unknown
  /// payload because production mode treats `metadata` as advisory rather
  /// than authoritative. Wrong-typed scalar fields fall back to defaults.
  /// Individually corrupt images are skipped; corrupt nested fields fall
  /// through to [ReportMetadata.fromJson]'s defensive parsing.
  factory ReportPayload.fromJson(Map<String, dynamic> json) {
    InspectMode parseMode(dynamic raw) {
      if (raw is String) {
        for (final m in InspectMode.values) {
          if (m.name == raw) return m;
        }
      }
      return InspectMode.production;
    }

    List<Uint8List> parseImages(dynamic raw) {
      if (raw is! List) return const <Uint8List>[];
      final out = <Uint8List>[];
      for (final item in raw) {
        if (item is String) {
          try {
            out.add(base64Decode(item));
          } catch (_) {/* skip non-base64 entries */}
        }
      }
      return out;
    }

    Map<String, Object?>? parseExtras(dynamic raw) {
      if (raw is! Map) return null;
      return <String, Object?>{
        for (final entry in raw.entries) entry.key.toString(): entry.value,
      };
    }

    final metaRaw = json['metadata'];
    final metadata = metaRaw is Map<String, dynamic>
        ? ReportMetadata.fromJson(metaRaw)
        : ReportMetadata.empty();

    return ReportPayload(
      mode: parseMode(json['mode']),
      userDescription: json['userDescription'] is String
          ? json['userDescription'] as String
          : '',
      images: parseImages(json['images']),
      metadata: metadata,
      extras: parseExtras(json['extras']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReportPayload &&
        other.mode == mode &&
        other.userDescription == userDescription &&
        listEquals(other.images, images) &&
        other.metadata == metadata &&
        mapEquals(other.extras, extras);
  }

  @override
  int get hashCode => Object.hash(
        mode,
        userDescription,
        Object.hashAll(images),
        metadata,
        Object.hashAllUnordered(extras.entries.map((e) => e.key)),
      );
}

/// Signature for the single submission callback both modes use.
typedef ReportSubmittedCallback = Future<void> Function(ReportPayload payload);
