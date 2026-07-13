/// Names shared between the two Flutter engines and the Android layer.
///
/// Transport map:
///  * `MediaListenerService` (native) → background engine: MethodChannel
///    [backgroundChannelName], method `playerEvent`.
///  * Background engine → native: same channel, method `ready` (returns
///    init args such as the files directory).
///  * UI engine → native (`MainActivity`): MethodChannel
///    [controlChannelName] — permission checks, settings intents, service
///    rebind.
///  * UI engine ↔ background engine (same process, pure Dart):
///    `IsolateNameServer` ports [bgControlPortName] / [uiSnapshotPortName].
library;

const String backgroundChannelName = 'scrobblr/scrobble/background';
const String controlChannelName = 'scrobblr/scrobble/control';

/// Registered by the background isolate; accepts
/// `{'type': 'credentialsChanged' | 'configChanged' | 'snapshotRequest'}`.
const String bgControlPortName = 'app.scrobblr.bg.control';

/// Registered by the UI when the pipeline monitor is visible; receives
/// snapshot maps of shape `{'type': 'pipeline', 'active': {...}?, ...}`.
const String uiSnapshotPortName = 'app.scrobblr.ui.snapshots';

/// SharedPreferences keys (written by the UI, read by the background
/// isolate after a `configChanged` ping).
const String prefDisabledSources = 'scrobblr.disabled_sources';
const String prefScrobblingEnabled = 'scrobblr.scrobbling_enabled';

/// User-added scrobble sources (Android package names) beyond the built-in
/// known list; they parse with the generic parser.
const String prefCustomSources = 'scrobblr.custom_sources';

/// Whether apps not in the known/custom source lists may scrobble via the
/// generic fallback parser. Defaults to true (historic behavior); turning it
/// off makes the sources list an allowlist.
const String prefCatchAllEnabled = 'scrobblr.catch_all_enabled';
