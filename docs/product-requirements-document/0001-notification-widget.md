# PRD: Notification Widget

| | |
|---|---|
| **Status** | Draft |
| **Date** | 2026-11-17 |
| **Audience** | Single user (personal use) |
| **Repository** | [github.com/adrianeyre/notification-widget](https://github.com/adrianeyre/notification-widget) |
| **Related** | [GLOSSARY.md](../../GLOSSARY.md), [ADR 0001](../architectural-decision-record/0001-floating-panel-not-widgetkit.md), [ADR 0002](../architectural-decision-record/0002-slack-socket-mode.md) |

Terms in **bold** are defined in the glossary.

## 1. Problem

Upcoming meetings, Slack DMs and Mentions, and important email are spread across three apps. Native macOS notifications are brief: they disappear after a few seconds and end up stacked in Notification Center. There's no single view that stays on screen and answers "what needs my attention right now?". A notification that arrives while you're focused elsewhere is easy to miss.

## 2. Goal

A persistent, widget-like **Panel** on the macOS desktop. It shows **Items** from Google Calendar, Gmail and Slack in one place and draws attention to new ones with an optional sound and shake (**Alert**), configured per **Source**.

### Non-goals (v1)

- Reading or replacing native macOS notifications. The app **supplements** them.
- Write-back to Sources: no marking as read, replying or RSVPing.
- More than one **Account** per Source.
- Distribution: no App Store, notarization, Google OAuth verification or Slack Marketplace listing.
- A native WidgetKit widget (see ADR 0001).
- Platforms other than the current macOS version the user runs.

## 3. Constraints and dependencies

- **Work accounts.** A Google Workspace admin must allow the Google OAuth client, and a Slack workspace admin must approve the Slack app and its user event scopes. **This is a launch blocker. Start the approval process first.**
- The Google OAuth client can stay in "testing" mode with the user as the only test user.
- The Slack app must have Socket Mode enabled (ADR 0002).

## 4. Users and scenarios

There is one user: the developer, on their own Mac, during the working day.

1. **Missed DM.** Someone DMs the user while they're working full-screen in an editor. The Panel comes to the front, shakes and plays the Slack sound. The user sees the sender and the start of the message, then clicks to open the conversation in the Slack app.
2. **Meeting reminder.** Ten minutes before a meeting (the **Reminder Time**), the Panel Alerts with the calendar sound and shows a countdown. The user clicks **Join** to open the Meet or Zoom link.
3. **Deep work.** A macOS Focus mode is on. New Items still appear on the Panel, but there are no sounds or shakes.
4. **Presenting.** The user shares their whole screen on a call. The Panel doesn't appear in the share.
5. **Morning start.** The user logs in. The app starts automatically, loads existing unread mail and Slack activity silently (**Backfill**), and shows today's Events, without a burst of Alerts.

## 5. Functional requirements

Priority uses MoSCoW: **M**ust, **S**hould, **C**ould.

### 5.1 Sources and Items

| ID | Requirement | Pri |
|---|---|---|
| SRC-1 | Connect one Google account (Calendar and Gmail) via an in-app OAuth sign-in. | M |
| SRC-1a | Connect one Slack workspace by pasting the user token (`xoxp-…`) and app-level token (`xapp-…`) into Settings. | M |
| SRC-2 | **DM** Items: Slack direct messages and group direct messages to the user. | M |
| SRC-3 | **Mention** Items: Slack messages that @mention the user, and replies in threads the user has posted in. | M |
| SRC-4 | **Email** Items: unread mail in the Gmail Primary inbox. The filter is stored as a Gmail search query (default `in:inbox category:primary is:unread`) that the user can change. | M |
| SRC-5 | **Event** Items: today's Google Calendar Events the user hasn't declined. | M |
| SRC-6 | All-day Events are shown in a compact header and never Alert. | M |
| SRC-7 | Slack keyword highlights as an extra Item kind. | C |
| SRC-8 | An in-app Slack OAuth sign-in instead of pasting tokens. | C |

### 5.2 Panel

| ID | Requirement | Pri |
|---|---|---|
| PNL-1 | A borderless, widget-styled Panel owned by a menu bar app (ADR 0001). | M |
| PNL-2 | The Panel normally sits at desktop level (behind application windows). | M |
| PNL-3 | Setting: keep the Panel always on top. | M |
| PNL-4 | The Panel can be dragged and remembers its position and screen across restarts. | M |
| PNL-5 | Sections are grouped by Source in this order: Events (next Event prominent), then DMs and Mentions, then Emails. Each section shows at most 5 Items plus "+N more". | M |
| PNL-6 | The Panel is excluded from screen sharing and screenshots. | M |
| PNL-7 | Setting: allow the Panel to be captured. | C |
| PNL-8 | Each section shows a health indicator (connected, out of date, disconnected, needs sign-in) with a one-click **Reconnect**. | M |
| PNL-9 | The menu bar menu gives access to Settings, showing or hiding the Panel, and Quit. | M |

### 5.3 What each Item shows

| ID | Requirement | Pri |
|---|---|---|
| ITM-1 | Email: sender and subject. No body preview. | M |
| ITM-2 | DM or Mention: sender, channel name or "DM", and the first ~100 characters of the message. | M |
| ITM-3 | Event: start time and title. A live countdown when the Event starts within 15 minutes. | M |
| ITM-4 | Event: a **Join** button when the Event has a Google Meet or Zoom link. | S |
| ITM-5 | An Item that has caused an Alert stays highlighted until it's clicked or **Dismissed**. | M |

### 5.4 Interaction

| ID | Requirement | Pri |
|---|---|---|
| INT-1 | Clicking a DM or Mention opens it in the Slack desktop app via a deep link. | M |
| INT-2 | Clicking an Email or Event opens it in the default browser. | M |
| INT-3 | **Dismiss** hides an Item locally and changes nothing at the Source. | M |

### 5.5 Alerts

| ID | Requirement | Pri |
|---|---|---|
| ALR-1 | Each Source has separate on/off toggles for **sound** and **shake** (6 toggles in total). | M |
| ALR-2 | Each Source has its own sound, chosen from the macOS system sounds, with a distinct default for each. | M |
| ALR-3 | When an Alert fires, the Panel comes to the front briefly, shakes if shake is enabled, then returns to desktop level. | M |
| ALR-4 | Alerts arriving close together are combined into one per Source within a ~10-second window. | M |
| ALR-5 | An Alert fires once and doesn't repeat. | M |
| ALR-6 | Event Alerts fire at the Reminder Time: the Event's own reminder, or 10 minutes before the start if it has none. | M |
| ALR-7 | While a macOS Focus mode is on, Alerts make no sound and don't shake. Items still appear. | M |
| ALR-8 | There are no Alerts during Backfill (launch or reconnect). An Event whose Reminder Time falls while the app is running still Alerts. | M |
| ALR-9 | Setting: a per-Source override to ignore Focus. | C |
| ALR-10 | Separate Alert settings for DM vs Mention. | C |
| ALR-11 | Custom sound files. | C |
| ALR-12 | Repeat the Alert for an Event that is starting now until it's acknowledged. | C |

### 5.6 When Items leave the Panel

| ID | Requirement | Pri |
|---|---|---|
| LIF-1 | An Email is removed when Dismissed, or when it no longer matches the filter (for example, it was read elsewhere). | M |
| LIF-2 | A DM or Mention is removed when Dismissed, when Slack reports the conversation as read (best effort), or 24 hours after it arrived. | M |
| LIF-3 | An Event is removed when it ends or is Dismissed. | M |

### 5.7 App behaviour

| ID | Requirement | Pri |
|---|---|---|
| APP-1 | Starts at login. On by default and can be switched off. | M |
| APP-2 | Dismissals and settings survive restarts. Items aren't stored as the source of truth; they're rebuilt from the Sources (Backfill). | M |
| APP-3 | OAuth tokens are stored in the macOS Keychain. | M |
| APP-4 | Reconnects automatically after network loss or sleep and wake, then runs a Backfill. | M |

## 6. Technical approach

- **Stack:** native Swift, SwiftUI for the views, and AppKit (`NSPanel`) for window-level control. Targets only the current macOS version the user runs.
- **Code structure:** domain logic lives in a local Swift package (tested with `swift test`, using Swift Testing). The Xcode app target is a thin shell around it.
- **Google sign-in:** Google's OAuth flow for installed apps (browser, loopback redirect, PKCE), implemented in the core package, with tokens in the Keychain and refreshed before use. The OAuth client is entered in Settings (ADR 0003).
- **Slack sign-in:** tokens are pasted into Settings and stored in the Keychain. Slack user tokens don't expire unless token rotation is turned on.
- **Slack:** Socket Mode with user-token event subscriptions, plus a Web API catch-up on launch and reconnect (ADR 0002). The app filters channel messages for the user's ID and keeps a set of threads the user has posted in.
- **Gmail:** polls every ~30 seconds using `history.list`, with a full query on Backfill.
- **Google Calendar:** polls every ~5 minutes for today's Events, and schedules Reminder Time Alerts locally.
- **Focus detection:** via the Focus status API, which requires user permission.
- **Screen capture exclusion:** via the window's sharing type.

## 7. Success criteria (v1)

v1 is successful if, over **one week of daily use**:

1. New DMs, Mentions and Emails appear on the Panel, and Alert where enabled, within **60 seconds**.
2. **No** Event Alerts are missed.
3. No restarts or manual reconnects are needed, apart from genuine sign-in expiry, which the health indicator shows.
4. The Panel is never captured in a screen share.

## 8. Risks and open issues

| Risk | Mitigation |
|---|---|
| A workspace admin refuses the Google or Slack OAuth apps. | Request approval before building. If Slack is refused, polling with a user token is a weaker fallback, but it may also need approval. |
| Slack read-state detection is unreliable (LIF-2). | The 24-hour expiry and Dismiss act as backstops. |
| Thread-reply Mentions are missed for threads the user posted in before the app started. | Build the set of the user's threads from recent history during Backfill. Accept that a few may be missed. |
| Double sounds: native notifications and this app's Alerts both play. | The user can turn off sound in the native Slack and Mail notification settings, or turn off this app's sound per Source. |
| The Google OAuth refresh token expires after 7 days while the client is in "testing" mode. | Detect it and show "needs sign-in" (PNL-8). If it becomes a nuisance, consider making the client "internal" to the Workspace. |
