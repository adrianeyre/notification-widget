# Releases and CI

[← Back to the README](../../README.md)

One workflow, [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml), runs on every pull request and every push to `main`:

```text
build-and-test ─▶ release (main only) ─▶ site ─▶ deploy (main only)
```

| Job | Runs on | What it does |
|---|---|---|
| Core tests and app build | Every PR and push | `swift test` for the core package and an unsigned `xcodebuild build`, on macOS, with SwiftPM caching |
| Release | Pushes to `main` | semantic-release: picks the next version from the commits, tags it and publishes a GitHub release with notes |
| Build the website | Every PR and push | Builds `site/` (typecheck, then Vite). On `main` it's stamped with the latest release and uploaded for Pages |
| Deploy to GitHub Pages | Pushes to `main` | Publishes the site to <https://notification-widget.adrianeyre.co.uk> |

## Versions

[semantic-release](https://semantic-release.gitbook.io/) reads the [Conventional Commits](https://www.conventionalcommits.org/) since the last `v*` tag:

| Commit | Release |
|---|---|
| `fix: …` | Patch, 1.0.**1** |
| `feat: …` | Minor, 1.**1**.0 |
| `feat!: …` or a `BREAKING CHANGE:` footer | Major, **2**.0.0 |
| `docs:`, `ci:`, `chore:`, `refactor:`, `test:` | No release |

With squash merges, the **pull request title** is the commit message, so give PRs a Conventional Commits title. The first release is `v1.0.0`. The configuration is in [`.releaserc.json`](../../.releaserc.json), and the tooling is pinned in the root `package.json` and `package-lock.json` (the app itself has no Node code).

### The version in the app

Nothing in the project is bumped for a release; the tag is the version. Every build runs [`scripts/stamp-version.sh`](../../scripts/stamp-version.sh), which writes the latest `v*` tag into the built app's Info.plist: `CFBundleShortVersionString` (`1.2.0`), `CFBundleVersion` (the commit count) and `NWGitDescription` (`git describe`). Settings → General and the menu bar menu show it. Without git or tags, for example in CI's shallow checkout, the app keeps the `0.0.0` fallback from `Config/Base.xcconfig`.

## GitHub Pages and the custom domain

One-time repository settings:

1. **Settings → Pages → Build and deployment → Source: GitHub Actions.**
2. **Settings → Pages → Custom domain:** `notification-widget.adrianeyre.co.uk`, then **Enforce HTTPS** once the certificate is issued. The site also ships a `CNAME` file with that domain.
3. At your DNS provider, add a **CNAME** record for `notification-widget` pointing to `adrianeyre.github.io`.
4. Optional: verify the domain under your GitHub account's **Settings → Pages**, so no other repository can claim it.
