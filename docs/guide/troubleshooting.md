# Troubleshooting

[← Back to the README](../../README.md)

| Problem | What to do |
|---|---|
| Settings → Accounts → Google says **Not set up** | Enter the Client ID and Client secret under **Google → Setup** ([setup](installation.md#step-5-enter-the-clients-and-connect)). |
| Google sign-in says **invalid_client** | The Client ID or secret is wrong, or the client isn't of type *Desktop app*. Check them under **Google → Setup**. |
| Google sign-in says the app is **blocked** or **access denied** | Your Workspace admin hasn't allowed the OAuth client yet ([Google setup, step 4](../setup/google-oauth-client.md#4-get-the-workspace-admin-to-allow-the-client)). |
| The browser says sign-in is complete but the app didn't connect | Sign-in has 5 minutes to finish. Click **Connect** again and complete it in the browser that opens. |
| The Events or Emails column says **Needs sign-in** every week | The Google client is External in testing mode, where refresh tokens expire after 7 days. Ask your admin about making it Internal ([Google setup, step 2](../setup/google-oauth-client.md#2-configure-the-consent-screen)), or click **Sign in** each time. |
| Slack says the token wasn't accepted | Check you copied all of it: the user token starts `xoxp-`, the app-level token `xapp-`. A revoked token needs the app reinstalling ([Slack setup](../setup/slack-app.md)). |
| **Sign in with Slack** fails | Slack must accept the redirect URL `http://localhost:53682/slack/oauth/callback`, and nothing else may be using port 53682. Otherwise paste the user token instead. |
| A column says **Out of date** | Click **Reconnect**. It normally recovers by itself after sleep or a network drop. |
| No sound or shake | Check the category in Settings → Alerts, and whether a Focus is on (Alerts go quiet unless Ignore Focus is on). |
| Alerts still sound during a Focus | The app can only read Focus status when it's signed with your team ([optional signing](installation.md#step-3-optional-signing-for-focus)) and you've allowed Focus access. |
| The Panel isn't visible | Use **Show Panel** in the menu bar menu. It sits behind other windows by design; turn on **Always on top** if you prefer. |
| The Panel shows in a screen share | Turn off **Allow screen capture** in Settings → General. |
| The app doesn't start at login | Turn **Launch at login** on, and allow it in System Settings → General → Login Items. |
