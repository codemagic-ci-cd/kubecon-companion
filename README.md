# KubeCon Companion

An unofficial companion app for KubeCon + CloudNativeCon North America 2026 (Salt Lake City, Nov 9-12), built with Flutter for the web (PWA), Android and iOS, and shipped with [Codemagic](https://codemagic.io).

- **Schedule**: browse by day, search, filter by type and track, and star sessions to save them.
- **Session details**: prerequisites, speakers, and directions to the room.
- **Venue map**: our own indoor map, drawn per level, with pinch-zoom and a highlighted route. Step-by-step directions call out escalators, elevators and level changes. Off-site venues get walking directions.
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
| `tool/build_sessions.py` | `sessions.json` and `rooms_raw.json`, from the public Sessionize feed for the official schedule |
| `tool/build_venue.py` | `venue.json`: levels, rooms, landmarks, directions and off-site venues |
| `tool/build_happenings.py` | `happenings.json` and `info.json` |
| `tool/make_icons.py` | PWA, Android and iOS icons, with no dependencies |

The venue map is a schematic reconstruction of the official map, not to scale.

## Ship it with Codemagic

`codemagic.yaml` defines four workflows. Each one runs on every push to `main`:

| Workflow | What it does |
| --- | --- |
| `web` | Tests and builds the PWA, then deploys it to Firebase Hosting when the `firebase` env group provides `FIREBASE_TOKEN`. |
| `android` | Builds a release APK and an App Bundle. They are signed with the debug key unless you add a keystore. |
| `ios-simulator` | Builds an unsigned simulator `.app` for quick demos, with no Apple account needed. |
| `ios-release` | Signs the app, builds the IPA and uploads it to TestFlight through the `codemagic` App Store Connect integration. |

To set it up, connect the repo in Codemagic, add the integrations and env groups you need, and push. One codebase gives you three stores' worth of builds without anyone running a build on their own machine.
