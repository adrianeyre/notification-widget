import Foundation

/// The page the browser shows when Google or Slack redirects back to the app's loopback
/// port after sign-in (SRC-8). The receiver holds the browser's request open until the
/// code has been exchanged for a token, so the page reports what really happened.
///
/// One self-contained document: inline styles, the services' marks as data URIs (SVGL,
/// MIT; see `site/stageshow/kit/brands/SOURCES.md`), a strict Content-Security-Policy and
/// no external requests. Light and dark follow the system, and motion respects Reduce Motion.
public enum OAuthCallbackPage {
    public enum Service: Sendable {
        case google
        case slack

        var name: String {
            switch self {
            case .google: "Google"
            case .slack: "Slack"
            }
        }

        /// Matches the Account's subtitle in Settings → Accounts.
        var covers: String {
            switch self {
            case .google: "Calendar and Gmail"
            case .slack: "DMs and Mentions"
            }
        }

        var loading: String {
            switch self {
            case .google: "Notification Widget is loading today’s Events and your unread Emails."
            case .slack: "Notification Widget is loading your DMs and Mentions."
            }
        }

        /// The control in Settings → Accounts that starts sign-in again.
        var retry: String {
            switch self {
            case .google: "Connect"
            case .slack: "Sign in with Slack…"
            }
        }

        var marks: [(label: String, data: String)] {
            switch self {
            case .google: [("Google Calendar", Mark.googleCalendar), ("Gmail", Mark.gmail)]
            case .slack: [("Slack", Mark.slack)]
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        case signedIn
        /// The user chose Cancel or Deny on the service's page.
        case cancelled
        /// Anything else, with the message Settings shows too.
        case failed(String)
    }

    /// An HTTP/1.1 response carrying the page.
    public static func response(_ service: Service, _ outcome: Outcome) -> String {
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return http(status: "200 OK", body: html(service, outcome, nonce: nonce), nonce: nonce)
    }

    /// The reply to anything that isn't the callback, such as the browser's favicon request.
    public static let notFoundResponse = http(status: "404 Not Found", body: "Not found", nonce: nil, type: "text/plain")

    static func http(status: String, body: String, nonce: String?, type: String = "text/html") -> String {
        let script = nonce.map { "'nonce-\($0)'" } ?? "'none'"
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(type); charset=utf-8",
            "Content-Length: \(body.utf8.count)",
            // Nothing leaves the page: no fetches, no fonts, no frames, no referrer.
            "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; img-src data:; script-src \(script); base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
            "Referrer-Policy: no-referrer",
            "Cache-Control: no-store",
            "X-Content-Type-Options: nosniff",
            "Connection: close",
        ]
        return headers.joined(separator: "\r\n") + "\r\n\r\n" + body
    }

    static func html(_ service: Service, _ outcome: Outcome, nonce: String) -> String {
        let name = service.name
        let state: String
        let title: String
        let heading: String
        var body: String
        switch outcome {
        case .signedIn:
            state = "signed-in"
            title = "Connected to \(name)"
            heading = "You’re connected to \(name)"
            body = "<p>\(escape(service.loading)) You can close this tab and go back to the app.</p>"
        case .cancelled:
            state = "cancelled"
            title = "\(name) sign-in cancelled"
            heading = "Sign-in was cancelled"
            body = """
            <p>Nothing was shared with Notification Widget. To try again, open <b>Settings → Accounts</b> \
            and choose <b>\(escape(service.retry))</b>.</p>
            """
        case .failed(let message):
            state = "failed"
            title = "\(name) sign-in didn’t finish"
            heading = "Couldn’t connect to \(name)"
            body = """
            <p class="error">\(escape(message))</p>
            <p>Try again from <b>Settings → Accounts</b> in Notification Widget.</p>
            """
        }
        let marks = service.marks
            .map { #"<img src="data:image/svg+xml;base64,\#($0.data)" alt="" width="20" height="20">"# }
            .joined()
        let badge = outcome == .signedIn
            ? #"<span class="badge" data-animate><span class="before">Not connected</span><span class="after"><svg viewBox="0 0 12 12" aria-hidden="true"><path d="M3 6.2 5.1 8.3 9 4"/></svg>Connected</span></span>"#
            : #"<span class="badge"><span>Not connected</span></span>"#
        body += #"<p class="hint"><kbd>⌘</kbd><kbd>W</kbd> closes this tab</p>"#

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <meta name="robots" content="noindex">
        <title>\(escape(title)) · Notification Widget</title>
        <style>\(styles)</style>
        </head>
        <body data-state="\(state)">
        <main>
          <figure class="account" aria-label="\(escape(name)) in Settings → Accounts: \(outcome == .signedIn ? "Connected" : "Not connected")">
            <span class="tile\(marks.count > 1 ? " pair" : "")">\(marks)</span>
            <span class="who">
              <span class="name">\(escape(name)) \(badge)</span>
              <span class="covers">\(escape(service.covers))</span>
            </span>
          </figure>
          <h1>\(escape(heading))</h1>
          \(body)
        </main>
        <footer>Notification Widget</footer>
        <script nonce="\(nonce)">
        // Take the one-time code and state out of the address bar and history.
        history.replaceState(null, "", location.pathname);
        </script>
        </body>
        </html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // The Settings → Accounts card in miniature, on the Panel's quiet grey ground, in the
    // system font. One thing happens: on success the badge turns from "Not connected"
    // to "Connected".
    static let styles = """
    :root {
      --ground: #e9ebf0; --ground-2: #dfe3ea; --surface: #ffffff; --inset: #f5f5f7;
      --ink: #1d1d1f; --ink-2: #5f6168; --ink-3: #8a8c93; --line: rgb(0 0 0 / 0.08);
      --badge: #e8e8ed; --badge-ink: #6e6e73; --ok: #1e8e4e; --ok-soft: #dff3e6; --danger: #c4372f;
      --shadow: 0 1px 2px rgb(0 0 0 / 0.06), 0 12px 32px -8px rgb(30 35 50 / 0.18);
      color-scheme: light dark;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --ground: #1b1c1f; --ground-2: #141517; --surface: #2a2b2f; --inset: #333438;
        --ink: #f5f5f7; --ink-2: #b4b6bd; --ink-3: #8b8d94; --line: rgb(255 255 255 / 0.08);
        --badge: #3a3b40; --badge-ink: #a9abb2; --ok: #45d07a; --ok-soft: #1e3a29; --danger: #ff7b72;
        --shadow: 0 1px 0 rgb(255 255 255 / 0.04) inset, 0 16px 40px -12px rgb(0 0 0 / 0.6);
      }
    }
    * { box-sizing: border-box; }
    html { height: 100%; }
    body {
      min-height: 100%; margin: 0; display: grid; grid-template-rows: 1fr auto; place-items: center;
      padding: 32px 16px 20px; background: radial-gradient(120% 80% at 50% 0%, var(--ground), var(--ground-2));
      color: var(--ink); font: 15px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    main {
      width: min(100%, 440px); padding: 28px 32px 24px; border-radius: 22px;
      background: var(--surface); box-shadow: var(--shadow);
    }
    .account {
      display: flex; align-items: center; gap: 12px; margin: 0 0 24px; padding: 14px;
      border-radius: 14px; background: var(--inset);
    }
    .tile {
      flex: none; display: grid; place-items: center; width: 44px; height: 44px; border-radius: 10px;
      background: var(--surface); box-shadow: 0 0 0 1px var(--line);
    }
    .tile img { display: block; width: 22px; height: 22px; }
    /* Two marks pad evenly: 10px at the sides, 6px between. */
    .tile.pair { grid-auto-flow: column; justify-content: center; gap: 6px; width: 66px; }
    .tile.pair img { width: 20px; height: 20px; }
    .who { display: grid; gap: 2px; min-width: 0; }
    .name { display: flex; align-items: center; gap: 8px; font-weight: 600; font-size: 15px; line-height: 1.3; }
    .covers { color: var(--ink-2); font-size: 13px; line-height: 1.3; }
    .badge {
      display: inline-grid; padding: 3px 9px; border-radius: 999px; background: var(--badge);
      color: var(--badge-ink); font-size: 12px; font-weight: 600; line-height: 1.3; white-space: nowrap;
    }
    .badge > span { grid-area: 1 / 1; display: inline-flex; align-items: center; justify-content: center; gap: 4px; }
    .badge svg { width: 12px; height: 12px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
    .badge[data-animate] { background: var(--ok-soft); color: var(--ok); }
    .badge[data-animate] .before { visibility: hidden; }
    @media (prefers-reduced-motion: no-preference) {
      .badge[data-animate] { animation: badge 360ms 650ms cubic-bezier(.2, .7, .2, 1) backwards; }
      .badge[data-animate] .before { animation: out 240ms 650ms ease-in backwards; }
      .badge[data-animate] .after { animation: in 360ms 760ms cubic-bezier(.2, .7, .2, 1) backwards; }
      .badge[data-animate] path { stroke-dasharray: 10; animation: tick 300ms 900ms ease-out backwards; }
      /* Transform only: the card is readable even if animations never run. */
      main { animation: rise 420ms cubic-bezier(.2, .7, .2, 1); }
    }
    @keyframes badge { from { background: var(--badge); color: var(--badge-ink); } }
    @keyframes out { from { visibility: visible; opacity: 1; } to { visibility: visible; opacity: 0; transform: translateY(-4px); } }
    @keyframes in { from { opacity: 0; transform: translateY(4px); } }
    @keyframes tick { from { stroke-dashoffset: 10; } }
    @keyframes rise { from { transform: translateY(8px); } }
    h1 { margin: 0 0 8px; font-size: 22px; line-height: 1.25; font-weight: 700; letter-spacing: -0.01em; text-wrap: balance; }
    p { margin: 0 0 12px; color: var(--ink-2); text-wrap: pretty; }
    p b { color: var(--ink); font-weight: 600; }
    .error { color: var(--danger); font-weight: 500; }
    .hint {
      display: flex; align-items: center; gap: 4px; margin: 20px 0 0; padding-top: 16px;
      border-top: 1px solid var(--line); color: var(--ink-3); font-size: 13px;
    }
    kbd {
      display: inline-grid; place-items: center; min-width: 22px; height: 22px; padding: 0 5px; border-radius: 6px;
      background: var(--inset); box-shadow: 0 0 0 1px var(--line), 0 1px 0 var(--line);
      color: var(--ink-2); font: 600 12px/1 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
    }
    kbd + kbd { margin-right: 4px; }
    footer { padding-top: 20px; color: var(--ink-3); font-size: 12px; }
    @media (max-width: 420px) { main { padding: 24px 20px 20px; } h1 { font-size: 20px; } }
    """

    enum Mark {
        static let slack = "PHN2ZyBlbmFibGUtYmFja2dyb3VuZD0ibmV3IDAgMCAyNDQ3LjYgMjQ1Mi41IiB2aWV3Qm94PSIwIDAgMjQ0Ny42IDI0NTIuNSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiA+PGcgY2xpcC1ydWxlPSJldmVub2RkIiBmaWxsLXJ1bGU9ImV2ZW5vZGQiPjxwYXRoIGQ9Im04OTcuNCAwYy0xMzUuMy4xLTI0NC44IDEwOS45LTI0NC43IDI0NS4yLS4xIDEzNS4zIDEwOS41IDI0NS4xIDI0NC44IDI0NS4yaDI0NC44di0yNDUuMWMuMS0xMzUuMy0xMDkuNS0yNDUuMS0yNDQuOS0yNDUuMy4xIDAgLjEgMCAwIDBtMCA2NTRoLTY1Mi42Yy0xMzUuMy4xLTI0NC45IDEwOS45LTI0NC44IDI0NS4yLS4yIDEzNS4zIDEwOS40IDI0NS4xIDI0NC43IDI0NS4zaDY1Mi43YzEzNS4zLS4xIDI0NC45LTEwOS45IDI0NC44LTI0NS4yLjEtMTM1LjQtMTA5LjUtMjQ1LjItMjQ0LjgtMjQ1LjN6IiBmaWxsPSIjMzZjNWYwIiAvPjxwYXRoIGQ9Im0yNDQ3LjYgODk5LjJjLjEtMTM1LjMtMTA5LjUtMjQ1LjEtMjQ0LjgtMjQ1LjItMTM1LjMuMS0yNDQuOSAxMDkuOS0yNDQuOCAyNDUuMnYyNDUuM2gyNDQuOGMxMzUuMy0uMSAyNDQuOS0xMDkuOSAyNDQuOC0yNDUuM3ptLTY1Mi43IDB2LTY1NGMuMS0xMzUuMi0xMDkuNC0yNDUtMjQ0LjctMjQ1LjItMTM1LjMuMS0yNDQuOSAxMDkuOS0yNDQuOCAyNDUuMnY2NTRjLS4yIDEzNS4zIDEwOS40IDI0NS4xIDI0NC43IDI0NS4zIDEzNS4zLS4xIDI0NC45LTEwOS45IDI0NC44LTI0NS4zeiIgZmlsbD0iIzJlYjY3ZCIgLz48cGF0aCBkPSJtMTU1MC4xIDI0NTIuNWMxMzUuMy0uMSAyNDQuOS0xMDkuOSAyNDQuOC0yNDUuMi4xLTEzNS4zLTEwOS41LTI0NS4xLTI0NC44LTI0NS4yaC0yNDQuOHYyNDUuMmMtLjEgMTM1LjIgMTA5LjUgMjQ1IDI0NC44IDI0NS4yem0wLTY1NC4xaDY1Mi43YzEzNS4zLS4xIDI0NC45LTEwOS45IDI0NC44LTI0NS4yLjItMTM1LjMtMTA5LjQtMjQ1LjEtMjQ0LjctMjQ1LjNoLTY1Mi43Yy0xMzUuMy4xLTI0NC45IDEwOS45LTI0NC44IDI0NS4yLS4xIDEzNS40IDEwOS40IDI0NS4yIDI0NC43IDI0NS4zeiIgZmlsbD0iI2VjYjIyZSIgLz48cGF0aCBkPSJtMCAxNTUzLjJjLS4xIDEzNS4zIDEwOS41IDI0NS4xIDI0NC44IDI0NS4yIDEzNS4zLS4xIDI0NC45LTEwOS45IDI0NC44LTI0NS4ydi0yNDUuMmgtMjQ0LjhjLTEzNS4zLjEtMjQ0LjkgMTA5LjktMjQ0LjggMjQ1LjJ6bTY1Mi43IDB2NjU0Yy0uMiAxMzUuMyAxMDkuNCAyNDUuMSAyNDQuNyAyNDUuMyAxMzUuMy0uMSAyNDQuOS0xMDkuOSAyNDQuOC0yNDUuMnYtNjUzLjljLjItMTM1LjMtMTA5LjQtMjQ1LjEtMjQ0LjctMjQ1LjMtMTM1LjQgMC0yNDQuOSAxMDkuOC0yNDQuOCAyNDUuMSAwIDAgMCAuMSAwIDAiIGZpbGw9IiNlMDFlNWEiIC8+PC9nPjwvc3ZnPg=="
        static let gmail = "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgNDkuNCA1MTIgMzk5LjQyIj48ZyBmaWxsPSJub25lIiBmaWxsLXJ1bGU9ImV2ZW5vZGQiPjxnIGZpbGwtcnVsZT0ibm9uemVybyI+PHBhdGggZmlsbD0iIzQyODVmNCIgZD0iTTM0LjkxIDQ0OC44MThoODEuNDU0VjI1MUwwIDE2My43MjdWNDEzLjkxYzAgMTkuMjg3IDE1LjYyMiAzNC45MSAzNC45MSAzNC45MXoiLz48cGF0aCBmaWxsPSIjMzRhODUzIiBkPSJNMzk1LjYzNiA0NDguODE4aDgxLjQ1NWMxOS4yODcgMCAzNC45MDktMTUuNjIyIDM0LjkwOS0zNC45MDlWMTYzLjcyN0wzOTUuNjM2IDI1MXoiLz48cGF0aCBmaWxsPSIjZmJiYzA0IiBkPSJNMzk1LjYzNiA5OS43MjdWMjUxTDUxMiAxNjMuNzI3di00Ni41NDVjMC00My4xNDItNDkuMjUtNjcuNzgyLTgzLjc4Mi00MS44OTF6Ii8+PC9nPjxwYXRoIGZpbGw9IiNlYTQzMzUiIGQ9Ik0xMTYuMzY0IDI1MVY5OS43MjdMMjU2IDIwNC40NTUgMzk1LjYzNiA5OS43MjdWMjUxTDI1NiAzNTUuNzI3eiIvPjxwYXRoIGZpbGw9IiNjNTIyMWYiIGZpbGwtcnVsZT0ibm9uemVybyIgZD0iTTAgMTE3LjE4MnY0Ni41NDVMMTE2LjM2NCAyNTFWOTkuNzI3TDgzLjc4MiA3NS4yOTFDNDkuMjUgNDkuNCAwIDc0LjA0IDAgMTE3LjE4eiIvPjwvZz48L3N2Zz4="
        static let googleCalendar = "PHN2ZyB3aWR0aD0iNTEyIiBoZWlnaHQ9IjUxMiIgdmlld0JveD0iMCAwIDUxMiA1MTIiIGZpbGw9Im5vbmUiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGcgY2xpcC1wYXRoPSJ1cmwoI2NsaXAwXzUwNzJfMzc2NikiPjxwYXRoIGQ9Ik0zOTAuNzM2IDEyMS4yNjRIMTIxLjI2NFYzOTAuNzM2SDM5MC43MzZWMTIxLjI2NFoiIGZpbGw9IndoaXRlIi8+PHBhdGggZD0iTTM5MC43MzYgNTEyTDUxMiAzOTAuNzM2TDQ1MS4zNjggMzgwLjM5MkwzOTAuNzM2IDM5MC43MzZMMzc5LjY3IDQ0Ni4xOTZMMzkwLjczNiA1MTJaIiBmaWxsPSIjRUE0MzM1Ii8+PHBhdGggZD0iTTAgMzkwLjczNlY0NzEuNTc4QzAgNDkzLjkxMiAxOC4wODggNTEyIDQwLjQyIDUxMkgxMjEuMjY0TDEzMy43MTQgNDUxLjM2OEwxMjEuMjY0IDM5MC43MzZMNTUuMTk4IDM4MC4zOTJMMCAzOTAuNzM2WiIgZmlsbD0iIzE4ODAzOCIvPjxwYXRoIGQ9Ik01MTIgMTIxLjI2NFY0MC40MkM1MTIgMTguMDg4IDQ5My45MTIgMCA0NzEuNTggMEgzOTAuNzM2QzM4My4zNiAzMC4wNzIgMzc5LjY3MSA1Mi4yMDI3IDM3OS42NyA2Ni4zOTJDMzc5LjY3IDgwLjU4IDM4My4zNTkgOTguODcwNyAzOTAuNzM2IDEyMS4yNjRDNDE3LjU1NiAxMjguOTQ0IDQzNy43NjcgMTMyLjc4NCA0NTEuMzY4IDEzMi43ODRDNDY0Ljk2OSAxMzIuNzg0IDQ4NS4xOCAxMjguOTQ1IDUxMiAxMjEuMjY0WiIgZmlsbD0iIzE5NjdEMiIvPjxwYXRoIGQ9Ik01MTIgMTIxLjI2NEgzOTAuNzM2VjM5MC43MzZINTEyVjEyMS4yNjRaIiBmaWxsPSIjRkJCQzA0Ii8+PHBhdGggZD0iTTM5MC43MzYgMzkwLjczNkgxMjEuMjY0VjUxMkgzOTAuNzM2VjM5MC43MzZaIiBmaWxsPSIjMzRBODUzIi8+PHBhdGggZD0iTTM5MC43MzYgMEg0MC40MjJDMTguMDg4IDAgMCAxOC4wODggMCA0MC40MlYzOTAuNzM2SDEyMS4yNjRWMTIxLjI2NEgzOTAuNzM2VjBaIiBmaWxsPSIjNDI4NUY0Ii8+PHBhdGggZD0iTTE3Ni41NCAzMzAuMzA4QzE2Ni40NjggMzIzLjUwNCAxNTkuNDk0IDMxMy41NjggMTU1LjY4OCAzMDAuNDI4TDE3OS4wNjYgMjkwLjc5NkMxODEuMTg2IDI5OC44OCAxODQuODkxIDMwNS4xNDUgMTkwLjE4MiAzMDkuNTkyQzE5NS40MzYgMzE0LjAzOCAyMDEuODM2IDMxNi4yMjggMjA5LjMxNCAzMTYuMjI4QzIxNi45NTkgMzE2LjIyOCAyMjMuNTI3IDMxMy45MDMgMjI5LjAxOCAzMDkuMjU0QzIzNC41MSAzMDQuNjA2IDIzNy4yNzIgMjk4LjY3OCAyMzcuMjcyIDI5MS41MDRDMjM3LjI3MiAyODQuMTYgMjM0LjM3NSAyNzguMTY0IDIyOC41ODIgMjczLjUxNkMyMjIuNzg4IDI2OC44NjggMjE1LjUxMiAyNjYuNTQ0IDIwNi44MjIgMjY2LjU0NEgxOTMuMzE0VjI0My40MDRIMjA1LjQ0QzIxMi45MTcgMjQzLjQwNCAyMTkuMjE2IDI0MS4zODIgMjI0LjMzNiAyMzcuMzM4QzIyOS40NTYgMjMzLjI5OCAyMzIuMDE2IDIyNy43NzIgMjMyLjAxNiAyMjAuNzMyQzIzMi4wMTYgMjE0LjQ2OCAyMjkuNzI2IDIwOS40ODIgMjI1LjE0NiAyMDUuNzQ0QzIyMC41NjYgMjAyLjAwNCAyMTQuNzcgMjAwLjExOCAyMDcuNzMgMjAwLjExOEMyMDAuODU4IDIwMC4xMTggMTk1LjQwMiAyMDEuOTM4IDE5MS4zNiAyMDUuNjA4QzE4Ny4zMTkgMjA5LjI4OSAxODQuMjgyIDIxMy45MzcgMTgyLjUzNCAyMTkuMTE2TDE1OS4zOTQgMjA5LjQ4MkMxNjIuNDU4IDIwMC43OTIgMTY4LjA4NCAxOTMuMTEyIDE3Ni4zMzYgMTg2LjQ3NkMxODQuNTg4IDE3OS44NCAxOTUuMTMyIDE3Ni41MDYgMjA3LjkzMiAxNzYuNTA2QzIxNy4zOTggMTc2LjUwNiAyMjUuOTIgMTc4LjMyNiAyMzMuNDY2IDE4MS45OTZDMjQxLjAxIDE4NS42NjggMjQ2LjkzOCAxOTAuNzU0IDI1MS4yMTYgMTk3LjIyMkMyNTUuNDk2IDIwMy43MjIgMjU3LjYxNiAyMTAuOTk4IDI1Ny42MTYgMjE5LjA4MkMyNTcuNjE2IDIyNy4zMzQgMjU1LjYzIDIzNC4zMDggMjUxLjY1NiAyNDAuMDM0QzI0Ny42ODIgMjQ1Ljc2IDI0Mi43OTYgMjUwLjEzOCAyMzcuMDAyIDI1My4yMDRWMjU0LjU4NEMyNDQuNDgzIDI1Ny42NjkgMjUwLjk4MiAyNjIuNzM1IDI1NS43OTggMjY5LjIzOEMyNjAuNjgyIDI3NS44MDYgMjYzLjE0MiAyODMuNjU0IDI2My4xNDIgMjkyLjgxOEMyNjMuMTQyIDMwMS45NzggMjYwLjgxNiAzMTAuMTY0IDI1Ni4xNjggMzE3LjMzOEMyNTEuNTIgMzI0LjUxNCAyNDUuMDg4IDMzMC4xNzIgMjM2LjkzNCAzMzQuMjgyQzIyOC43NSAzMzguMzkyIDIxOS41NTQgMzQwLjQ4MiAyMDkuMzQ4IDM0MC40ODJDMTk3LjUyNCAzNDAuNTE0IDE4Ni42MTIgMzM3LjExMiAxNzYuNTQgMzMwLjMwOFpNMzIwLjEzMiAyMTQuMjk4TDI5NC40NjYgMjMyLjg1OEwyODEuNjMyIDIxMy4zOUwzMjcuNjc4IDE4MC4xNzZIMzQ1LjMyOFYzMzYuODQySDMyMC4xMzJWMjE0LjI5OFoiIGZpbGw9IiM0Mjg1RjQiLz48L2c+PGRlZnM+PGNsaXBQYXRoIGlkPSJjbGlwMF81MDcyXzM3NjYiPjxyZWN0IHdpZHRoPSI1MTIiIGhlaWdodD0iNTEyIiBmaWxsPSJ3aGl0ZSIvPjwvY2xpcFBhdGg+PC9kZWZzPjwvc3ZnPg=="
    }
}
