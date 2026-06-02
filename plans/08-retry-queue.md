# Plan 08 — Persistent retry queue for failed submissions

## Goal

When `onReportSubmitted` throws (flaky network, expired token, server 5xx), don't lose the report. Queue it to disk, replay on next app launch. Mobile UX expectation is "submit-and-forget."

Current behavior (after Plan 06): SnackBar tells the user, sheet stays open, typed text preserved. User must manually retry. That's fine for the explicit-retry case but not for "user typed feedback, hit send, walked into a tunnel, closed the app." That report is gone.

## API design

### `ShakeContext.guard` gains three parameters

```dart
ShakeContext.guard(
  () => runApp(const MyApp()),
  enableRetryQueue: true,                          // opt-in, default false
  retryQueueMaxAge: const Duration(days: 7),       // entries older are dropped
  retryQueueMaxEntries: 20,                        // FIFO eviction above this
);
```

### Three new static methods on `ShakeContext`

```dart
/// Number of queued reports awaiting replay. Use for a "Pending reports: N"
/// badge in a settings screen. Returns 0 when the queue is disabled.
static Future<int> queuedReportCount();

/// Manually trigger a replay pass. Use for a "Retry now" button. Returns
/// the number of successfully delivered reports.
static Future<int> replayQueuedReports();

/// Emergency drain — delete every queued report without trying to send.
static Future<void> clearQueuedReports();
```

### Lifecycle

1. **Submission failure** in either view: if queue enabled, `RetryQueue.enqueue(payload)` is called before the SnackBar shows. The payload is serialized with `includeImages: true` to a per-report JSON file under `<applicationSupportDirectory>/shake_context/queue/<uuid>.json`.
2. **`guard` startup**: if `enableRetryQueue: true` and the queue directory is non-empty, schedule `Future.delayed(const Duration(seconds: 5))` after `runApp` that replays each queued payload. The 5-second delay avoids competing with app boot for network/CPU.
3. **Eviction**:
   - On enqueue: if count > `retryQueueMaxEntries`, drop oldest by file mtime
   - On replay startup: drop entries with `queuedAt` older than `retryQueueMaxAge`
4. **Replay success** → delete the file. **Replay failure** → leave the file in place (next launch tries again, eviction caps staleness).

### Queue file format

```json
{
  "schemaVersion": 1,
  "queuedAt": "2026-05-19T16:32:00.000Z",
  "payload": { /* ReportPayload.toJson(includeImages: true) */ }
}
```

Schema-version mismatch on load → drop the entry rather than crash. Lets us evolve `ReportPayload` without breaking users mid-upgrade.

## Required prerequisite: `ReportPayload.fromJson`

Currently `ReportPayload` only has `toJson`. To round-trip a queued report we need:

```dart
factory ReportPayload.fromJson(Map<String, dynamic> json);
factory ReportMetadata.fromJson(Map<String, dynamic> json);
factory LogEntry.fromJson(Map<String, dynamic> json);
factory NetworkLog.fromJson(Map<String, dynamic> json);
```

Defensive parsing — every field tolerates missing/wrong-typed values. Bad entries surface as `null` returns at the queue level (we drop them).

## Files

| Action | Path |
|--------|------|
| New | `lib/src/core/retry_queue.dart` — `RetryQueue` class with `enqueue`, `replay`, `count`, `clear` |
| New | `lib/src/core/retry_queue_store.dart` — file-backed store, parallels `FilePersistenceStore` |
| Modified | `lib/src/models/report_payload.dart` — add `fromJson` factories |
| Modified | `lib/src/models/log_entry.dart` — add `fromJson` factory |
| Modified | `lib/src/models/network_log.dart` — add `fromJson` factory |
| Modified | `lib/src/shake_context_widget.dart` — `guard()` accepts new params, owns the `RetryQueue` instance, schedules replay 5s after boot |
| Modified | `lib/src/presentation/developer_view.dart` — on submission failure, enqueue before SnackBar |
| Modified | `lib/src/presentation/production_view.dart` — same |
| Modified | `lib/shake_context.dart` — export `RetryQueue` (for the static methods) |
| New | `test/core/retry_queue_test.dart` — full behavior matrix |
| New | `test/models/report_payload_fromjson_test.dart` — round-trip and defensive parsing |
| Modified | `README.md` — replace the manual "retry pattern" snippet with the real API |
| Modified | `CHANGELOG.md` — unreleased entry |

## Test plan

`test/core/retry_queue_test.dart` covers:

- `enqueue` writes a file with the expected JSON shape under a temp dir (test seam: `RetryQueue(directory: tempDir)`)
- `count` returns the number of files in the directory
- `replay` calls the host callback for each file in mtime order
- `replay` deletes the file on callback success
- `replay` leaves the file on callback failure
- Enqueue past `maxEntries` evicts oldest by mtime
- `replay` skips and deletes files older than `maxAge` without calling the callback
- `replay` skips and deletes files with a `schemaVersion` mismatch
- `clear` empties the directory
- Round-trip: an enqueued payload re-emerges from `replay` byte-identical (modulo image base64 → bytes)

Widget-level tests:

- Submission failure with `enableRetryQueue: true` results in a non-empty queue
- Submission failure with the queue disabled does not touch disk

`test/models/report_payload_fromjson_test.dart` covers:

- Round-trip: `ReportPayload.fromJson(payload.toJson(includeImages: true))` equals the original (modulo unmodifiable wrappers)
- Missing optional fields parse to defaults
- Wrong-typed fields parse to defaults (no throw)
- Empty `images` and `extras` work
- `mode` parses from string back to enum; unknown value falls back to `production` (safer for unknown payloads)

## Acceptance

- `flutter analyze` green
- `flutter test` green, all existing tests pass, +25 new tests minimum
- README "Sending the report → Handling submission failures" section rewritten to use the real API instead of the manual snippet
- CHANGELOG records the feature

## Risks & decisions

- **Stale auth tokens**: if `onReportSubmitted` uses a token that expired, replay fails forever for that entry. **Mitigation**: `retryQueueMaxAge` caps the damage at 7 days by default; entries silently drop after that.
- **Privacy footprint**: queued images sit on disk under `applicationSupportDirectory` until replayed. Goes with the app on uninstall. **Mitigation**: document explicitly in the README's privacy section; expose `clearQueuedReports()` for hosts who want a logout hook.
- **Disk space**: worst case is `maxEntries × per-report-size`. With default 20 × ~6 MB screenshots that's ~120 MB. **Mitigation**: document the math; recommend hosts using high-res screenshots tune `screenshotPixelRatio` down (already exposed) or `maxEntries` lower.
- **Schema version is a one-way upgrade**: bumping `schemaVersion` drops every queued report from previous versions. **Mitigation**: only bump on actual breaking shape changes; the version field exists precisely so we *can* drop safely instead of crashing on a field-shape mismatch.
- **Replay delay race**: if the host calls `replayQueuedReports()` manually before the 5s auto-replay fires, both could process the same file. **Mitigation**: `RetryQueue.replay` is reentrant — it uses file-rename-on-success as the atomic claim, so the second caller sees an empty queue.

## Sequencing within the plan

1. `fromJson` factories on the models (prerequisite, smallest risk)
2. `RetryQueue` + store + tests in isolation
3. Wire into `guard()` and the two views
4. End-to-end widget test for the full failure → next-launch-replay loop
5. README + CHANGELOG
