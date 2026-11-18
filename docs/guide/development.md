# Development

[← Back to the README](../../README.md)

## Project layout

| Path | What's there |
|---|---|
| `App/NotificationWidget/` | The app target: menu bar, Panel window and views, Settings, and the Google, Slack and Focus wiring. UI and wiring only. |
| `Packages/NotificationWidgetCore/` | A local Swift package with all the domain logic: Items, the Item store and Dismissals, settings, the Calendar, Gmail and Slack Sources and their API clients, the Alert engine, Reminder Time scheduling and Source health. Tested with Swift Testing. |
| `Config/` | Build settings. The optional `Secrets.xcconfig` (git-ignored) holds your signing team. The Google and Slack clients are entered in the app, not here. |
| `project.yml` | The XcodeGen spec that `NotificationWidget.xcodeproj` is generated from. |
| `site/` | The project website, built with Vite and the Stageshow kit and published to GitHub Pages. |
| `docs/` | The PRD, ADRs, setup guides and these guides. |

The design decisions are in the [PRD](../product-requirements-document/0001-notification-widget.md) and the ADRs: [floating panel, not WidgetKit](../architectural-decision-record/0001-floating-panel-not-widgetkit.md) and [Slack through Socket Mode](../architectural-decision-record/0002-slack-socket-mode.md) and [Google sign-in without the SDK](../architectural-decision-record/0003-google-oauth-without-sdk.md). Use the words in the [glossary](../../GLOSSARY.md) in code and UI.

## Tests

```sh
swift test --package-path Packages/NotificationWidgetCore
```

Domain logic is written test-first where practical, with injected clocks and fake APIs, so the tests never touch the network.

## Running without Accounts

Launch with **`-UseSampleItems YES`** to fill the Panel with hard-coded Items instead of real Sources. In Xcode: **Product → Scheme → Edit Scheme → Run → Arguments**. The sample stand-up's Reminder Time is 2 minutes after launch, so it also shows an Event Alert.

## Screenshots

The Panel is hidden from screenshots, so the images in `docs/images/` are rendered by the app itself. In a Debug build:

```sh
APP="build/DerivedData/Build/Products/Debug/Notification Widget.app"
"$APP/Contents/MacOS/Notification Widget" -UseSampleItems YES -SnapshotDir docs/images
```

That writes `panel-light.png`, `panel-dark.png` and one `settings-*.png` per Settings tab. Run it from the repository root: the Panel shots load the sample people's portraits from `site/public/avatars/`. Use a copy without Accounts set up, or leave the `settings-*.png` files out of the commit, because the Settings shots show this Mac's real setup state.

The people in the screenshots and on the website are invented, and so are their faces. `site/scripts/avatars.mjs` draws them as small SVGs standing in for Slack photos and Gravatars. A few people (Payroll, GitHub, a group DM) have no portrait, so the pictures show the initials fallback too. To change them, edit the list in the script and run `node scripts/avatars.mjs` from `site/`.

## Changing the project

Edit `project.yml`, then regenerate the Xcode project and commit both:

```sh
xcodegen generate
```

## The website

```sh
cd site
npm install
npm run dev     # local preview
npm run build   # writes site/dist/
```

See `site/REHEARSAL.md` for how the demos were checked. `site/public/og.png` (the link preview) is the hero's poster frame, the reduced-motion still, at 2×: the `.pg-hero-demo` figure plus 16 px of page around it, at a 1280 px wide window.

## Commit messages

Releases are automatic (see [Releases and CI](releases-and-ci.md)), so commits and pull request titles follow [Conventional Commits](https://www.conventionalcommits.org/): `feat: …` for a feature, `fix: …` for a fix, `docs:`, `ci:`, `refactor:` and so on for the rest.
