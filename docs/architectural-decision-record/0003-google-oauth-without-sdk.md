# Google sign-in without the GoogleSignIn SDK

Google sign-in uses Google's OAuth flow for installed apps directly: the browser, a redirect back to `http://127.0.0.1` on a free port, and PKCE (RFC 8252, RFC 7636), with a Google Cloud client of type **Desktop app**. Tokens are kept in the Keychain and refreshed by the app. We replaced the GoogleSignIn SDK so that the Google client can be entered in Settings at run time. The SDK refuses to start a sign-in unless the client's reversed ID is registered as a URL scheme in the app's Info.plist, which is fixed when the app is built.

## Considered Options

- **Keep GoogleSignIn, client ID in a build setting** (the previous approach): every change to the client meant editing `Config/Secrets.xcconfig` and rebuilding, and Keychain storage needed the Keychain Sharing entitlement, so a signed build with an Apple team.
- **Keep GoogleSignIn and register a URL scheme at run time**: not possible; a signed app's Info.plist can't change.
- **Our own installed-app flow** (chosen): the same loopback receiver as Sign in with Slack, about 200 lines in the core package, covered by tests including a real loopback round trip.

## Consequences

- The Google client and the Slack OAuth client are entered in **Settings → Accounts → Setup**; client IDs go in preferences, secrets and tokens in the Keychain. `Config/Secrets.xcconfig` is now optional and only sets a signing team (for Focus status).
- Existing Google clients of type iOS need replacing with a **Desktop app** client; an existing sign-in has to be redone once.
- The app owns token refresh and revocation. A refused refresh token (revoked, or expired after 7 days in testing mode) shows "needs sign-in" as before.
