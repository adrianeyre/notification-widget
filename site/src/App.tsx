import { PanelHero } from './demos/panel/PanelHero'
import { Bento } from './demos/bento/Bento'

const REPO = 'https://github.com/adrianeyre/notification-widget'
const DOC = (path: string) => `${REPO}/blob/main/${path}`
const VERSION = __SITE_VERSION__

export function App() {
  return (
    <>
      <header className="pg-bar">
        <div className="pg-wrap pg-bar-inner">
          <a className="pg-wordmark" href="/">
            Notification Widget
          </a>
          <a className="pg-bar-link" href={REPO}>
            GitHub
          </a>
        </div>
      </header>

      <main>
        <section className="pg-hero pg-wrap" aria-labelledby="hero-title">
          <div className="pg-hero-copy">
            <h1 id="hero-title">What needs you today, on your desktop.</h1>
            <p className="pg-lead">
              A macOS menu bar app with a Panel for today’s Events, unread Emails, and Slack DMs and Mentions. When something new arrives, you hear it and see it.
            </p>
            <div className="pg-actions">
              <a className="pg-button pg-button--primary" href={REPO}>
                View on GitHub
              </a>
              <a className="pg-button" href={`${REPO}#quick-start`}>
                Set up
              </a>
            </div>
          </div>
          <figure className="pg-hero-demo" aria-label="The Panel: a Slack DM arrives highlighted, the Panel shakes, and opening it clears the highlight.">
            <PanelHero />
          </figure>
        </section>

        <section className="pg-section pg-wrap" aria-labelledby="features-title">
          <h2 id="features-title">Calm until something needs you.</h2>
          <Bento />
        </section>

        <section className="pg-section pg-wrap" aria-labelledby="how-title">
          <h2 id="how-title">How it works</h2>
          <ul className="pg-facts">
            <li>
              <b>Read-only.</b> It never marks anything read, replies or changes anything at the Source.
            </li>
            <li>
              <b>Seen, even in full screen.</b> An Alert lifts the Panel above full-screen windows for a moment, then it returns to the desktop.
            </li>
            <li>
              <b>Quiet when it should be.</b> Silent during a Focus unless you turn on Ignore Focus, and the Backfill at launch never Alerts.
            </li>
            <li>
              <b>Stays connected.</b> A health indicator for each Source with one-click Reconnect, and it reconnects after sleep or a lost network.
            </li>
          </ul>
        </section>

        <section className="pg-section pg-wrap" aria-labelledby="start-title">
          <h2 id="start-title">Get started</h2>
          <p className="pg-note">
            It’s a personal app you build in Xcode. You’ll need a Google OAuth client and a Slack app, each approved by your workspace admin.
          </p>
          <ol className="pg-steps">
            <li>
              <a href={DOC('docs/setup/google-oauth-client.md')}>Set up the Google OAuth client</a>
              <span>Calendar and Gmail, read-only scopes.</span>
            </li>
            <li>
              <a href={DOC('docs/setup/slack-app.md')}>Set up the Slack app</a>
              <span>Socket Mode with user-token events.</span>
            </li>
            <li>
              <a href={`${REPO}#quick-start`}>Build and run</a>
              <span>Open the project in Xcode and press Run.</span>
            </li>
          </ol>
        </section>
      </main>

      <footer className="pg-footer">
        <div className="pg-wrap pg-footer-inner">
          <span>
            Notification Widget{VERSION ? <span className="pg-version"> {VERSION.startsWith('v') ? VERSION : `v${VERSION}`}</span> : null}
          </span>
          <a href={REPO}>Source on GitHub</a>
          <span className="pg-marks">Slack, Gmail, Google Calendar and Google Meet are trademarks of their owners.</span>
        </div>
      </footer>
    </>
  )
}
