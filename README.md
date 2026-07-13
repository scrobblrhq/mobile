# newfm mobile

Android scrobbler for newfm: a persistent notification listener detects what
any player is playing, a debounced/deduplicated pipeline decides what counts
as a listen, and a Material You UI shows the enriched catalog the backend
builds in the background.

```
┌────────────────────────── Android process ──────────────────────────┐
│                                                                     │
│  MediaListenerService (Kotlin, NotificationListenerService)         │
│    · notification-access permission gates MediaSessionManager       │
│    · diffs active sessions, one callback per player                 │
│    · thin sensor: forwards raw events, interprets nothing           │
│            │ MethodChannel `newfm/scrobble/background`              │
│            ▼                                                        │
│  Background FlutterEngine (headless, no UI needed)                  │
│    scrobbleServiceMain → ScrobbleService                            │
│      parser registry ─ ScrobbleEngine (debounce/dedupe/thresholds)  │
│      → now-playing + scrobble submissions (API token)               │
│      → offline PendingQueue (JSON file, backoff retry)              │
│            │ IsolateNameServer (same-process Dart ports)            │
│            ▼                                                        │
│  UI FlutterEngine (MainActivity)                                    │
│    Material You (dynamic_color) · live now-playing via SSE          │
│    recent/top/artist screens fed by enriched metadata               │
└─────────────────────────────────────────────────────────────────────┘
                     │ HTTP (session token for reads,
                     ▼        API token for scrobbling)
                newfm API (crates/api)
```

## Decisions

### Background service architecture

- **`NotificationListenerService` + `MediaSessionManager`, not notification
  text parsing.** Holding notification access is what authorizes
  `MediaSessionManager.getActiveSessions()`, which yields structured
  `MediaMetadata` (title/artist/album/duration) and `PlaybackState` for every
  player — locale-independent and identical to what the media notification
  renders. The event model keeps an `origin` field (`media_session` /
  `notification`) so true text parsers can be added later for players
  without sessions.
- **Persistence without a foreground notification.** The system keeps
  notification listeners bound and rebinds them after crashes/reboots; the
  service also exposes `ensureServiceRunning` (engine boot +
  `requestRebind`) and Settings offers the battery-optimization exemption
  for aggressive OEMs.
- **Native is a sensor; Dart is the brain.** The Kotlin side only diffs
  sessions and forwards raw maps into a headless FlutterEngine
  (`BackgroundEngineHolder`, buffering events during engine boot). Parsing,
  debounce, dedupe, thresholds, submission and the offline queue live in
  pure Dart (`lib/scrobbling/`) with no Flutter imports — the entire
  pipeline is unit-tested with a fake clock (`flutter test`).
- **Two engines, one process.** The UI talks to the background isolate over
  `IsolateNameServer` ports: config/credential pings in one direction, live
  pipeline snapshots (the Home screen "scrobbler monitor") in the other. No
  polling through native code.

### Source → parser mapping

`ParserRegistry` maps the player's Android package name to a `SourceParser`
(`lib/scrobbling/source_parsers.dart`); unknown packages fall back to a
generic parser so *any* media app scrobbles:

| Package | Parser | Notes |
|---|---|---|
| `com.spotify.music` | `SpotifyParser` | rejects ad breaks |
| `...apps.youtube.music` | `YoutubeMusicParser` | strips `- Topic` artists |
| `com.google.android.youtube` | `YoutubeParser` | strips `(Official Video)`-style decoration, splits `Artist - Title`, falls back to channel name flagged low-confidence |
| Tidal/Deezer/Apple/Amazon/VLC/Poweramp | `GenericParser` with named slug | trusted as-is |
| anything else | `GenericParser` | source `android` |

The parser's slug is submitted as the scrobble's `source`, so the backend
records *where* each listen happened. Individual sources can be toggled off
in Settings (`SharedPreferences`, re-read by the background isolate on
ping).

### Dedupe / debounce

State machine in `ScrobbleEngine` (per media session, deterministic,
clock-injected):

1. **Debounce**: a track change must survive a 5 s settle window while
   playing before it is accepted — skipping through a playlist emits
   nothing. Acceptance sends **now-playing** once.
2. **Play accounting**: wall-clock time accumulates only while `PLAYING`;
   pauses and ad breaks freeze it. A quick A→B→A flip within the settle
   window keeps A's accumulated time.
3. **Scrobble threshold** (kept strictly inside the server's rules —
   `listened ≥ 30 s or ≥ 50 %`): `max(30 s, min(50 % of duration, 4 min))`;
   4 min when the duration is unknown; tracks under 30 s never scrobble.
   `played_at` is the listen *start* (last.fm semantics), submitted with
   `listened_ms`.
4. **One scrobble per play session**; a position snap back to ≤ 5 s after a
   scrobble (repeat-one, manual restart) starts a new session.
5. **Client dedupe mirror**: identical track submissions within 30 s are
   dropped before hitting the server's duplicate check.
6. **Offline queue**: failed submissions land in a JSON-file queue (cap
   500) and retry with exponential backoff (30 s·2ⁿ, ≤ 30 min); permanent
   4xx rejections are dropped, not retried.

### Auth model

Sign-in creates a **session token** (kept for UI reads — the
`optional_auth` routes only honor sessions) and immediately provisions a
named, scoped **API token** (`POST /v1/auth/tokens`, scope `scrobble`) for
the background service — it survives "logout all devices" and is revoked on
sign-out. Both live in `flutter_secure_storage` (readable by both engines).

### UI + metadata fallbacks

Material 3 with `dynamic_color`: wallpaper-derived ColorSchemes on
Android 12+, harmonized; brand seed (`#C51224`) elsewhere. Enrichment is
asynchronous by design (the worker fills MBIDs, covers, artist images and
bios after first scrobble), so missing metadata is a first-class state:

- `Artwork` widget cascade: enriched URL → while-loading/on-error → a
  gradient placeholder derived from the *current* dynamic scheme
  (primary/tertiary containers) with artist initials or a note glyph.
- Artist detail shows a "Metadata pending" card with a working **Refresh
  metadata** action (`POST /v1/artist/{id}/refresh`) when the bio is
  missing, and a "MusicBrainz linked" badge once enriched.
- Optional fields (album, duration) simply collapse; the pipeline monitor
  marks YouTube-title guesses as "(guessed)".
- Live now-playing card streams `/v1/user/{name}/live` (SSE, auto-
  reconnect) with a progress bar interpolated from `started_at`/
  `expires_at`.

## Layout

```
lib/
  main.dart            UI entrypoint + @pragma('vm:entry-point') scrobbleServiceMain
  app.dart             DynamicColorBuilder + auth gate
  api/                 HTTP client + Dart mirrors of shared models (incl. SSE)
  auth/                credential store (secure storage) + sign-in/out flow
  scrobbling/          PURE DART: events, parsers, engine, rules, queue  ← tested
  background/          headless service, channel/port protocol, UI facade
  ui/                  shell, screens (home/stats/artist/settings/login), widgets
android/app/src/main/kotlin/fm/newfm/mobile/
  MainActivity.kt                     control channel (permission, rebind, battery)
  scrobble/MediaListenerService.kt    NotificationListenerService + session diffing
  scrobble/BackgroundEngineHolder.kt  headless engine lifecycle + event buffering
```

## Running it

Requires the Flutter SDK (stable ≥ 3.29) with the Android toolchain — not
part of the devenv shell. No `flutter create` step is needed: the Gradle
wrapper is materialized by the Flutter tool and the launcher icon is a
committed adaptive vector (minSdk 26).

```bash
cd apps/mobile
flutter pub get
flutter test                  # parsers, engine, queue, login smoke test
flutter run                   # emulator: server default http://10.0.2.2:8080 works as-is
```

Backend: `devenv up` + `cargo run -p api` (and `cargo run -p worker` to see
enrichment fill in covers/bios). Physical device: `adb reverse tcp:8080
tcp:8080` and use `http://127.0.0.1:8080` as the server URL, or point at a
LAN address.

First run: sign in (or create an account), then grant **notification
access** from the Home banner or Settings. Play something in any music app;
the Home monitor shows the pipeline settle → track → scrobble in real time.

Turbo wraps the app as `@/mobile` (build/test/lint/fmt no-op with a notice
when the Flutter SDK is absent, so repo-wide `turbo run build` stays green).

## Known limitations

- Release builds are debug-signed until a real signing config is added.
- One scrobble source of truth for artwork is the backend; notification
  album art bitmaps are not forwarded (kept off the channel on purpose).
- `flutter_secure_storage`'s encrypted prefs need Google Play-less devices
  to support Keystore (standard requirement).
- iOS is out of scope: notification-listener scrobbling is
  Android-specific.
