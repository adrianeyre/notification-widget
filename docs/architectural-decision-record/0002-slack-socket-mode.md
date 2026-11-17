# Slack updates arrive through Socket Mode, not polling

DMs and Mentions reach the app through Slack Socket Mode, using user-token event subscriptions. Slack pushes events over a WebSocket that the app opens. A one-off Web API catch-up runs at launch and after every reconnect (the Backfill). We chose this over polling the Web API because Slack's rate limits make 30-second polling of many conversations impractical, and polling can't detect replies in threads the user takes part in without re-reading every thread. Socket Mode gives real-time delivery without a public server.

## Consequences

- The Slack app must be created with Socket Mode enabled. It needs an app-level token (`connections:write`) as well as the user token, and the workspace admin has to approve the user event scopes (DM, group DM and channel message events).
- Mentions are found by filtering channel message events for the user's ID. Thread Mentions require the app to track which threads the user has posted in.
- Socket Mode apps can't be listed in the Slack Marketplace. That's acceptable, because this app is for personal use only.
