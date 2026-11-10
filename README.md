# KubeCon Companion

An unofficial companion app for KubeCon + CloudNativeCon North America 2026 (Salt Lake City, Nov 9-12), built with Flutter for the web (PWA), Android and iOS, and shipped with [Codemagic](https://codemagic.io).

- **Schedule**: browse by day, search, filter by type and track, and star sessions to save them.
- **Session details**: prerequisites, speakers, and directions to the room.
- **Venue map**: the official KubeCon venue map with our room boxes and walking graph on top. Tap a room for what's on now and next; directions draw the route on the map and page through steps (escalators, elevators, step-free option). Off-site venues get walking directions.
- **Now**: lunch, coffee breaks, receptions and other happenings, with a "happening now / up next" banner.
- **Reminders**: a notification 10 minutes before highlights and your saved sessions.

## Run

```sh
flutter pub get
flutter run -d chrome          # web
flutter run                    # connected Android/iOS device
flutter test
```

To demo the app as if it were a conference day, open the web app with `?now=2026-11-10T12:40` (venue time). Add `&tab=map`, `&tab=now` or `&tab=saved` to open a tab directly.

## Build

```sh
flutter build web --release --no-web-resources-cdn   # offline-capable PWA in build/web
flutter build apk --release
flutter build ipa                                    # needs Xcode + signing
```

The web build registers `web/sw.js`, which caches the app for offline use. Flutter's own service worker is not registered, because it only unregisters itself. `--no-web-resources-cdn` bundles CanvasKit with the app instead of loading it from a CDN.

## Data

Everything the app shows comes from `assets/data/*.json`, which is bundled with the app, so it works offline. The scripts in `tool/` regenerate those files:

| Script | Output |
| --- | --- |
| `tool/build_sessions.py` | `schedule.json` (loaded at startup), `details.json` (descriptions and bios, loaded after the first frame) and `rooms_raw.json`, from the public Sessionize feed for the official schedule |
| `tool/build_share_pages.py` | `web/s/<id>.html`: one static page per session with its own link preview (title, time, room, speakers), forwarding to the app. Rerun after `build_sessions.py` |
| `tool/build_venue.py` | `venue.json`: levels, rooms, landmarks, directions and off-site venues |
| `tool/build_happenings.py` | `happenings.json` and `info.json` |
| `tool/make_icons.py` | PWA, Android and iOS icons, with no dependencies |

The venue map image is the official one (KubeCon + CloudNativeCon / Linux Foundation, https://events.linuxfoundation.org/kcna26-venue-map); room boxes and the walking graph are annotated by us in `assets/data/map_salt_palace.json` and `assets/data/map_hyatt.json` and merged with `python3 -I tool/merge_official_map.py`. The map is not to scale, so walking times are estimates.

## Ship it with Codemagic

`codemagic.yaml` defines four workflows. Each one runs on every push to `main`:

| Workflow | What it does |
| --- | --- |
| `web` | Tests and builds the PWA, then deploys it to Firebase Hosting when the `firebase` env group provides `FIREBASE_TOKEN`. |
| `android` | Builds a release APK and an App Bundle. They are signed with the debug key unless you add a keystore. |
| `ios-simulator` | Builds an unsigned simulator `.app` for quick demos, with no Apple account needed. |
| `ios-release` | Signs the app, builds the IPA and uploads it to TestFlight through the `codemagic` App Store Connect integration. |

To set it up, connect the repo in Codemagic, add the integrations and env groups you need, and push. One codebase gives you three stores' worth of builds without anyone running a build on their own machine.

## Shared agenda links open the app

Agenda links (`https://kubecon.codemagic.app/?agenda=a1.…`) open the installed app, which offers the import. The site serves the verification files from `web/.well-known/`:

- `assetlinks.json` (Android App Links) lists the SHA-256 fingerprint of the upload key in `~/.kubecon-companion-signing/upload.jks`. **When the Play listing exists, add the Play App Signing key fingerprint too** (Play Console > Test and release > App integrity), or links from Play installs stay in the browser.
- `apple-app-site-association` (iOS Universal Links) names `X8NNQ9CYL2.io.codemagic.kubeconCompanion` and matches only URLs with an `agenda` query. The App ID needs the Associated Domains capability, and the App Store profile must be created after it was enabled.

Both must be served with HTTP 200 and a JSON content type at `https://kubecon.codemagic.app/.well-known/…`.
