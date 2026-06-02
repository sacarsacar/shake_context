/// shake_context — a dual-mode, privacy-first, shake-triggered bug reporting
/// and user feedback engine for Flutter.
///
/// See the `plans/` directory at the repository root for the rollout sequence.
library;

export 'src/core/persistence_store.dart'
    show PersistenceStore, SessionSnapshot, FilePersistenceStore;
export 'src/core/retry_queue.dart' show RetryQueue;
export 'src/core/retry_queue_store.dart'
    show RetryQueueStore, RetryQueueEntry;
export 'src/models/config_options.dart';
export 'src/models/inspect_mode.dart';
export 'src/models/log_entry.dart';
export 'src/models/network_log.dart';
export 'src/models/production_strings.dart';
export 'src/models/redaction_config.dart';
export 'src/models/report_payload.dart';
export 'src/models/report_theme.dart';
export 'src/models/shake_sensitivity.dart';
export 'src/shake_context_widget.dart';
