import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { ChevronsUpDown, EyeOff } from 'lucide-react'
import { BrandMark, Button, Connector, Count, Stage, Toggle, useReducedMotion, type Act, type Rect } from '../../../stageshow/kit'
import { usePrefersDark } from '../../usePrefersDark'
import './bento.css'

// The features grid (references/bento.md). Five tiles, hero and strip.
//
//   Tile      Span   Kind        The one thing                         Moves
//   Alerts    2 x 1  Hero UI     DMs and Mentions Alert settings       Shake for Mentions turns on
//   Speed     1 x 1  Stat        "60 s", on the one dark tile          counts up to 60
//   Sources   1 x 1  Diagram     three Source marks into the Panel     the lines draw in
//   Private   1 x 1  Statement   "Hidden from screen sharing."         holds still
//   Join      1 x 1  Component   an Event starting now, with Join      Join presses
//
// The hero demo above already shows the Panel, so no tile repeats it: no
// window chrome anywhere in the grid, and no string or mark used twice. Each
// picture is its own Stage at 1:1, pinned to its tile's bottom; the copy is
// page text. Each tile plays one beat, once, 110ms after the tile before it.

const STEP = 110
const LEAD = 450

type Beat = { on: boolean }
const before: Beat = { on: false }
const after: Beat = { on: true }
const beat = (i: number) => async (a: Act<Beat>) => {
  await a.wait(LEAD + i * STEP)
  await a.set({ on: true })
}

function Tile({ area, title, children, picture, dark }: { area: string; title: ReactNode; children?: ReactNode; picture?: ReactNode; dark?: boolean }) {
  return (
    <section className={`nb-tile nb-tile--${area}`} data-dark={dark || undefined} data-crop>
      {title ? (
        <p className="nb-copy">
          {title} {children}
        </p>
      ) : (
        children
      )}
      {picture}
    </section>
  )
}

// The tile owns the crop: an inner Stage matches the picture slot's width.
function usePictureWidth() {
  const ref = useRef<HTMLDivElement>(null)
  const [width, setWidth] = useState(340)
  useLayoutEffect(() => {
    const node = ref.current
    if (!node) return
    const measure = () => setWidth(Math.max(1, Math.round(node.getBoundingClientRect().width)))
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(node)
    return () => observer.disconnect()
  }, [])
  return [ref, width] as const
}

/* ---------------- Alerts (hero) ---------------- */

// A row is a switch (on or off) or, with null, a picker showing its value
function Group({ label, rows }: { label: string; rows: [string, boolean | null, string?][] }) {
  return (
    <div className="nb-group">
      <div className="nb-group-label">{label}</div>
      <div className="nb-group-card">
        {rows.map(([name, on, value]) => (
          <div key={name} className="nb-setting">
            <span className="nb-setting-name">{name}</span>
            {value && (
              <span className="nb-setting-value">
                {value}
                <ChevronsUpDown size={13} strokeWidth={2} aria-hidden />
              </span>
            )}
            {on !== null && <Toggle on={on} className="nb-toggle" />}
          </div>
        ))}
      </div>
    </div>
  )
}

function Alerts() {
  const [picture, width] = usePictureWidth()
  const dark = usePrefersDark()
  const narrow = width < 560
  return (
    <Tile
      area="hero"
      title={<b>Alerts your way.</b>}
      picture={
        <div ref={picture} className="nb-picture nb-picture--full">
          <Stage<Beat> width={width} height={narrow ? 172 : 278} initial={before} poster={after} play="once" script={beat(0)} theme={dark ? 'dark' : 'light'} className="nb-stage">
            {(s) => (
              <div className="nb-settings" data-narrow={narrow || undefined}>
                <Group label="DMs" rows={narrow ? [['Sound', true], ['Shake', true]] : [['Sound', true], ['Alert sound', null, 'Glass'], ['Shake', true], ['Ignore Focus', true]]} />
                <Group label="Mentions" rows={narrow ? [['Sound', true], ['Shake', s.on]] : [['Sound', true], ['Alert sound', null, 'Ping'], ['Shake', s.on], ['Ignore Focus', false]]} />
              </div>
            )}
          </Stage>
        </div>
      }
    >
      A sound, a shake or both, set for each Source and for DMs and Mentions separately.
    </Tile>
  )
}

/* ---------------- Speed (stat) ---------------- */

function useInView<T extends Element>(delay: number) {
  const ref = useRef<T>(null)
  const [seen, setSeen] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    let t = 0
    const io = new IntersectionObserver(
      ([e]) => {
        if (!e.isIntersecting) return
        io.disconnect()
        t = window.setTimeout(() => setSeen(true), delay)
      },
      { threshold: 0.4 },
    )
    io.observe(el)
    return () => {
      io.disconnect()
      clearTimeout(t)
    }
  }, [delay])
  return [ref, seen] as const
}

function Speed() {
  const reduced = useReducedMotion()
  const [ref, seen] = useInView<HTMLDivElement>(LEAD + STEP)
  return (
    <Tile area="stat" dark title={null}>
      <div ref={ref} className="nb-stat">
        <span className="nb-stat-lead">New Items appear within</span>
        <span className="nb-stat-number">
          <Count value={seen || reduced ? 60 : 15} duration={1100} />
          <span className="nb-stat-unit">&nbsp;s</span>
        </span>
        <span className="nb-stat-label">Slack is real time, over Socket Mode.</span>
      </div>
    </Tile>
  )
}

/* ---------------- Sources (diagram) ---------------- */

const SOURCES = [
  { brand: 'slack', name: 'Slack' },
  { brand: 'gmail', name: 'Gmail' },
  { brand: 'google-calendar', name: 'Google Calendar' },
] as const

function Sources() {
  const [picture, width] = usePictureWidth()
  const dark = usePrefersDark()
  return (
    <Tile
      area="sources"
      title={<b>One place.</b>}
      picture={
        <div ref={picture} className="nb-picture nb-picture--full">
          <Stage<Beat> width={width} height={206} initial={before} poster={after} play="once" script={beat(2)} theme={dark ? 'dark' : 'light'} className="nb-stage">
            {(s, rect) => {
              const right = (r: Rect) => ({ x: r.x + r.width, y: r.y + r.height / 2 })
              const left = (r: Rect) => ({ x: r.x, y: r.y + r.height / 2 })
              const to = rect('panel')
              return (
                <>
                  <div className="nb-sources">
                    {SOURCES.map((m) => (
                      <span key={m.brand} className="nb-source" data-target={`s-${m.brand}`}>
                        <BrandMark brand={m.brand} size={20} tile={false} />
                        <span>{m.name}</span>
                      </span>
                    ))}
                  </div>
                  <span className="nb-node" data-target="panel" data-on={s.on || undefined}>
                    <span className="nb-node-strip" aria-hidden>
                      <i />
                      <i />
                      <i />
                    </span>
                    <span>Panel</span>
                  </span>
                  {to &&
                    SOURCES.map((m, i) => {
                      const from = rect(`s-${m.brand}`)
                      return from ? <Connector key={m.brand} from={right(from)} to={left(to)} route="step" show={s.on} className={`nb-line nb-line--${i}`} /> : null
                    })}
                </>
              )
            }}
          </Stage>
        </div>
      }
    >
      Today’s Events, Primary Emails, DMs, Mentions and thread replies.
    </Tile>
  )
}

/* ---------------- Private (statement) ---------------- */

function Private() {
  return (
    <Tile area="private" title={null}>
      <div className="nb-statement">
        <EyeOff className="nb-statement-icon" size={32} strokeWidth={2} aria-hidden />
        <p className="nb-statement-text">
          Hidden from screen sharing. <span>And from screenshots.</span>
        </p>
      </div>
    </Tile>
  )
}

/* ---------------- Join (component) ---------------- */

function Join() {
  const [picture, width] = usePictureWidth()
  const dark = usePrefersDark()
  return (
    <Tile
      area="join"
      title={<b>Join from the Panel.</b>}
      picture={
        <div ref={picture} className="nb-picture nb-picture--full">
          <Stage<Beat> width={width} height={206} initial={before} poster={after} play="once" script={beat(4)} theme={dark ? 'dark' : 'light'} className="nb-stage">
            {(s) => (
              <div className="nb-event">
                <div className="nb-event-top">
                  <BrandMark brand="google-meet" size={28} />
                  <span className="nb-event-text">
                    <span className="nb-event-title">Weekly sync</span>
                    <span className="nb-event-when">14:00–14:30</span>
                  </span>
                </div>
                <div className="nb-event-foot">
                  <span className="nb-event-now">Starting now</span>
                  <Button variant="primary" size="large" className="nb-event-join" data-on={s.on || undefined}>
                    Join
                  </Button>
                </div>
              </div>
            )}
          </Stage>
        </div>
      }
    >
      An Alert at the Reminder Time, repeated until you respond.
    </Tile>
  )
}

export function Bento() {
  return (
    <div className="nw-bento">
      <div className="nb-grid">
        <Alerts />
        <Speed />
        <Sources />
        <Private />
        <Join />
      </div>
    </div>
  )
}
