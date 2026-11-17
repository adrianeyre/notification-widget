# Floating panel owned by a menu bar app, not a WidgetKit widget

The display is a borderless panel owned by a menu bar app. It normally sits at desktop level and comes to the front briefly when an Alert fires. We did not build a native macOS desktop widget (WidgetKit), even though "desktop widget" was the starting idea. WidgetKit widgets can't play sounds or animate in response to new data, and their timeline refresh budget can't deliver near-real-time (30 to 60 second) updates. Sound and shake Alerts, and that freshness, are core requirements.

## Considered Options

- **WidgetKit widget plus companion app**: the most native look, but no sound, no shake, and throttled refreshes.
- **Übersicht (HTML desktop widgets)**: quick to prototype, but OAuth token refresh and sound playback are unreliable from its shell or JS sandbox.
- **Menu bar app with a floating panel** (chosen): full control over the window level, animation, audio and update timing.

## Consequences

- The Panel has to imitate widget styling itself and won't appear in the macOS widget gallery or Notification Center.
- The app has to manage the panel's window level (desktop level, temporarily raised on an Alert, optionally always on top) and remember its position.
