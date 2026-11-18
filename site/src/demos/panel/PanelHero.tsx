import { useEffect, useState } from 'react'
import { AtSign, MessageCircle, X } from 'lucide-react'
import { Avatar, Button, Collapse, Count, Icon, Row, Stage, useReducedMotion, type Act, type Layout } from '../../../stageshow/kit'
import { usePrefersDark } from '../../usePrefersDark'
import './panel.css'

// The hero: the Panel on a strip of desktop. A Slack DM arrives, highlighted,
// and the Panel gives a small shake; the cursor opens it and the highlight
// clears; then it Dismisses the DM, which is the loop's visible reset. The
// next Event's countdown ticks throughout and never rewinds.
//
// Plan, written before building:
//   Place   a full-width hero under the page's headline, 1120 x 300 at 1:1,
//           with a 358 x 340 compact design for a phone column
//   Focal   the new DM row in DMs and Mentions
//   Action  the DM drops in highlighted, the Panel shakes, the cursor clicks it
//   Payoff  the highlight clears; the countdown is still running
//   Leave   window chrome, the menu bar, Settings, health states

type S = { dm: boolean; seen: boolean; shake: boolean }

const initial: S = { dm: false, seen: false, shake: false }
// The poster: the DM has arrived and is highlighted
const POSTER: S = { dm: true, seen: false, shake: false }

const REST = { wide: { x: 1062, y: 236 }, compact: { x: 342, y: 300 } }

async function script(a: Act<S>) {
  await a.wait(1400)
  // 1. A DM arrives: the row drops in, highlighted, and the Panel shakes
  await a.set({ dm: true })
  await a.wait(260)
  await a.set({ shake: true })
  await a.wait(700)
  await a.set({ shake: false })
  await a.wait(1100)

  // 2. The cursor opens it, and the highlight clears
  await a.move({ at: 'dm', x: a.layout === 'compact' ? 0.62 : 0.5, y: 0.93 })
  await a.wait(450)
  await a.click()
  await a.set({ seen: true })
  await a.wait(2200)

  // 3. Dismiss: the × that hovering shows in place of the time
  await a.move('dismiss')
  await a.wait(300)
  await a.click()
  await a.set({ dm: false })
  await a.wait(900)
  // Hidden now, so its highlight is put back unseen
  await a.snap({ seen: false })
  await a.move('rest')
  await a.wait(900)
}

export function PanelHero() {
  const dark = usePrefersDark()
  return (
    <Stage<S>
      width={1120}
      height={300}
      compact={{ below: 640, width: 358, height: 340 }}
      initial={initial}
      poster={POSTER}
      script={script}
      cursor={{ at: REST }}
      theme={dark ? 'dark' : 'light'}
      fidelity="realistic"
      className="nw-hero"
    >
      {(s, _rect, layout) => (
        <>
          <Panel s={s} layout={layout} />
          <span data-target="rest" className="nw-rest" style={{ left: REST[layout].x, top: REST[layout].y }} />
        </>
      )}
    </Stage>
  )
}

/* ---------------- The Panel ---------------- */

function Panel({ s, layout }: { s: S; layout: Layout }) {
  const wide = layout === 'wide'
  const highlighted = s.dm && !s.seen
  return (
    <div className="nw-panel" data-shake={s.shake || undefined}>
      <div className="nw-head">
        <span className="nw-date">Tuesday 17 November</span>
        <span className="nw-new" data-show={highlighted || undefined}>
          1 new
        </span>
      </div>
      <div className="nw-columns" data-crop>
        {wide && (
          <>
            <Events />
            <span className="nw-rule" />
          </>
        )}
        <Messages s={s} />
        {wide && (
          <>
            <span className="nw-rule" />
            <Emails />
          </>
        )}
      </div>
    </div>
  )
}

function Header({ glyph, label, count }: { glyph: React.ReactNode; label: string; count: number }) {
  return (
    <div className="nw-col-head">
      <span className="nw-col-label">
        <span className="nw-glyph">{glyph}</span>
        {label}
      </span>
      <Count className="nw-col-count" value={count} duration={500} />
    </div>
  )
}

/* Events: an all-day chip, the next Event as a raised card, later Events */

function Events() {
  return (
    <section className="nw-col">
      <Header glyph={<Icon name="calendar" filled size={13} />} label="Events" count={6} />
      <div className="nw-allday">
        <span className="nw-chip">Company offsite</span>
      </div>
      <div className="nw-next">
        <div className="nw-next-text">
          <span className="nw-next-title">Sprint planning</span>
          <span className="nw-next-when">
            <span>09:30–09:45</span>
            <Countdown />
          </span>
        </div>
        <Button variant="primary" size="small" className="nw-join">
          Join
        </Button>
      </div>
      <div className="nw-later">
        {[
          ['11:00', 'Hiring sync'],
          ['15:55', 'Design review'],
          ['17:30', 'Team retro'],
          ['18:00', 'Book club'],
        ].map(([time, title]) => (
          <div key={time} className="nw-later-row">
            <span className="nw-later-time">{time}</span>
            <span className="nw-later-title">{title}</span>
          </div>
        ))}
      </div>
    </section>
  )
}

// The live countdown to the next Event: one tick a second on the stage's
// clock, never reset by the loop. Under reduced motion it holds still.
function Countdown() {
  const reduced = useReducedMotion()
  const [left, setLeft] = useState(11 * 60 + 59)
  useEffect(() => {
    if (reduced) return
    const id = window.setInterval(() => setLeft((n) => (n > 61 ? n - 1 : 11 * 60 + 59)), 1000)
    return () => window.clearInterval(id)
  }, [reduced])
  return (
    <span className="nw-countdown">
      in <Count value={left} duration={420} stagger={30} format={(n) => `${Math.floor(n / 60)}:${String(n % 60).padStart(2, '0')}`} />
    </span>
  )
}

/* DMs and Mentions */

type Message = { name: string; where: string; time: string; text: string; mention?: boolean }

const NEW_DM: Message = { name: 'Priya Shah', where: 'DM', time: '09:18', text: 'Can you check the release notes before standup?' }
const MESSAGES: Message[] = [
  { name: 'Tom Okafor', where: '#platform', time: '09:02', text: 'Deploy is green, can you merge the API change?', mention: true },
  { name: 'Lena Fischer', where: 'DM', time: '08:41', text: 'Thanks, that fixed it' },
  { name: 'Sam Reid', where: '#design', time: '08:15', text: 'New icons are in the shared folder', mention: true },
  { name: 'Nina Haas', where: 'DM', time: '07:50', text: 'See you at the offsite' },
  { name: 'Olu Adeyemi', where: '#support', time: '07:32', text: 'Ticket queue is clear for the morning', mention: true },
]

// Illustrated portraits of these invented people (public/avatars, drawn by
// scripts/avatars.mjs), standing in for Slack photos and Gravatars. Anyone missing
// here has none and shows initials, as the app does.
const PORTRAITS = new Set([
  'Priya Shah', 'Tom Okafor', 'Lena Fischer', 'Sam Reid', 'Nina Haas', 'Olu Adeyemi', 'Maria Lopez', 'Aisha Khan',
])
const portrait = (name: string) =>
  PORTRAITS.has(name) ? `/avatars/${name.toLowerCase().replace(/\s+/g, '-')}.svg` : undefined

function Person({ name, mention }: { name: string; mention?: boolean }) {
  return (
    <span className="nw-person">
      <Avatar name={name} size={24} src={portrait(name)} />
      {mention && (
        <span className="nw-at" aria-label="Mention">
          <AtSign size={8} strokeWidth={3} />
        </span>
      )}
    </span>
  )
}

function ItemRow({ m, target, highlighted }: { m: Message; target?: boolean; highlighted?: boolean }) {
  return (
    <Row
      pad={8}
      className="nw-row"
      data-target={target ? 'dm' : undefined}
      data-cursor={target ? 'pointer' : undefined}
      data-highlight={highlighted || undefined}
      lead={<Person name={m.name} mention={m.mention} />}
      title={
        <>
          {m.name}
          <span className="nw-where"> · {m.where}</span>
        </>
      }
      meta={
        <span className="nw-meta">
          <span className="nw-time">{m.time}</span>
          <span className="nw-dismiss" data-target={target ? 'dismiss' : undefined} aria-label="Dismiss">
            <X size={9} strokeWidth={3} />
          </span>
        </span>
      }
      subtitle={m.text}
    />
  )
}

function Messages({ s }: { s: S }) {
  return (
    <section className="nw-col">
      <Header glyph={<MessageCircle size={13} fill="currentColor" strokeWidth={1.5} />} label="DMs and Mentions" count={s.dm ? 6 : 5} />
      <div className="nw-list">
        <Collapse open={s.dm} reveal="drop">
          <ItemRow m={NEW_DM} target highlighted={!s.seen} />
        </Collapse>
        {MESSAGES.map((m) => (
          <ItemRow key={m.name} m={m} />
        ))}
      </div>
    </section>
  )
}

/* Emails */

const EMAILS: Message[] = [
  { name: 'Maria Lopez', where: '', time: '08:52', text: 'Q4 roadmap review' },
  { name: 'Jonas Berg', where: '', time: '08:30', text: 'Contract draft for review' },
  { name: 'Aisha Khan', where: '', time: '07:58', text: 'Offsite travel details' },
  { name: 'Dev Patel', where: '', time: '07:31', text: 'Expenses for October' },
]

function Emails() {
  return (
    <section className="nw-col">
      <Header glyph={<Icon name="mail" filled size={13} />} label="Emails" count={4} />
      <div className="nw-list">
        {EMAILS.map((m) => (
          <Row
            key={m.name}
            pad={8}
            className="nw-row"
            lead={<Person name={m.name} />}
            title={m.name}
            meta={
              <span className="nw-meta">
                <span className="nw-time">{m.time}</span>
              </span>
            }
            subtitle={m.text}
          />
        ))}
      </div>
    </section>
  )
}
