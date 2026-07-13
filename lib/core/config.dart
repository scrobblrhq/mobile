/// Compile-time defaults.
library;

/// The hosted newfm instance regular users sign in to. Self-hosters point
/// elsewhere via "Advanced options" on the login screen.
const String hostedServerUrl = 'https://newfm.app';

/// Dev server URL pre-filled in the advanced section of debug builds.
/// `10.0.2.2` is the Android emulator's alias for the host machine (where
/// `cargo run -p api` listens on 0.0.0.0:8080).
const String defaultServerUrl = 'http://10.0.2.2:8080';

/// SharedPreferences key remembering the last server a user signed in to
/// (written at sign-in and sign-out), so self-hosters keep their URL across
/// sessions even though the field is hidden by default.
const String prefLastServerUrl = 'newfm.last_server_url';

/// Name used when provisioning the device API token at sign-in.
const String apiTokenName = 'newfm mobile';
