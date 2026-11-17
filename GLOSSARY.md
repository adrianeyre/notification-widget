# Notification Widget

A personal macOS desktop display that brings together activity from Google Calendar, Gmail and Slack in one view on the desktop.

## Language

### Core

**Item**:
A single thing shown in the display that needs the user's attention, from one Source.
_Avoid_: Notification, alert, message (as the umbrella term)

**Source**:
One external service that Items come from: Slack, Gmail or Google Calendar.
_Avoid_: Integration, provider, channel

**Account**:
The user's identity on a Source (one Google account, one Slack workspace).
_Avoid_: Login, connection

### Item kinds

**DM**:
A Slack direct message or group direct message sent to the user.
_Avoid_: Private message, chat

**Mention**:
A Slack message that @mentions the user, or a reply in a Slack thread the user takes part in.
_Avoid_: Ping, tag

**Email**:
An unread message in the user's Gmail Primary inbox.
_Avoid_: Mail, message

**Event**:
A Google Calendar entry happening today that the user is attending.
_Avoid_: Meeting, appointment

### Interaction

**Dismiss**:
Hiding an Item from the display. Only the display changes; nothing is changed at the Source.
_Avoid_: Clear, mark as read, delete

### Attention

**Alert**:
The display's attention-grabbing reaction to a new Item: a sound, a shake of the Panel, or both, configured separately for each Source.
_Avoid_: Notification, ping, buzz

**Reminder Time**:
The moment an Event's Alert fires: the reminder set on the Event, or a default lead time when it has none.
_Avoid_: Notification time, alarm

**Panel**:
The floating, widget-like window on the desktop that shows Items.
_Avoid_: Widget, window, dashboard

**Backfill**:
Loading the Items that already exist when the app starts or reconnects. Backfilled Items appear silently and never cause an Alert.
_Avoid_: Sync, initial load, catch-up
