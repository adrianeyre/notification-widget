# Rehearsal: Notification Widget site

Two pictures, built with the vendored Stageshow kit (`stageshow/kit`, MIT, see `stageshow/LICENSE` and `stageshow/NOTICE.md`):

- `src/demos/panel/PanelHero.tsx`: the animated hero (the Panel)
- `src/demos/bento/Bento.tsx`: the feature grid (five tiles)

## Hero: the Panel

Gold: `examples/hero-demo` for the script shape (named targets, `a.move`/`a.click`, rest point, poster, compact), with the layout taken from `examples/raycast` and the framing table's "Stage with gutters" row. The Panel is a desktop widget, so it sits on a strip of desktop wallpaper.
- Kept: the five-part script with a rest target, the poster set to the payoff, a `compact` redesign, kit `Row`, `Avatar`, `Button`, `Collapse`, `Count`.
- Changed: no browser window. The Panel is drawn to the app's spec (940 x 320 at 1:1, 22pt corners, a regular-material blur, three columns with hairlines, the date header and the "1 new" pill). The stage is 1120 x 300, the Panel inset 90px (8%) at the sides and 40px from the top, running 60px off the bottom so the crop only cuts later rows.
- Compact (358 x 340, below 640): the DMs and Mentions column on its own, Panel 300 wide, inset 29px, off the bottom.

Beats: 1. A calm Panel (1.4 s). 2. A Slack DM drops in at the top of DMs and Mentions, highlighted; the count rolls 5 to 6, the "1 new" pill appears and the Panel shakes. 3. The cursor goes to the row and clicks; the highlight and pill clear. 4. Payoff holds (2.2 s). 5. Hovering the row shows the Dismiss in place of the time, and the cursor clicks it; the row collapses (this is the loop's visible reset). The next Event's countdown ("in 11:59") ticks once a second the whole time and never resets with the loop. Loop is about 11.5 s.

Poster (reduced motion, thumbnails): the DM has arrived and is highlighted, "1 new" showing. Under reduced motion the countdown holds still and the shake becomes a pulse.

Captured: 1280 (stage at 1:1) and 390 (compact), light and dark, reduced-motion poster at both widths, `--states`, plus a zoom on the countdown digits.

Gate (`film.mjs --gate`, last runs):
- 1280 light: `rehearsal passed (necessary, not sufficient: references/verify.md and the fresh eye in review.md still stand)`
- 1280 dark: `rehearsal passed (necessary, not sufficient: references/verify.md and the fresh eye in review.md still stand)`
- 390 light: `rehearsal passed (necessary, not sufficient: references/verify.md and the fresh eye in review.md still stand)`
- 390 dark: `rehearsal passed (necessary, not sufficient: references/verify.md and the fresh eye in review.md still stand)`
- 1280 `--states`: `rehearsal passed ...`

Film lines and what was done:
- `translucent icon` (column glyphs) → used an opaque grey for the glyphs.
- `touching` ("in" against the countdown digits) → a 4px gap.
- `layout` (Panel content past its padding) → columns given a fixed height that clips at the Panel's padding, as the real Panel clips its list. Compact got its own height.
- `uneven inset` (avatar and Dismiss in the row) → row side padding 13/12 with the list's negative margin, so words still line up with the column header.
- `hard edge` (compact column clipping a moving row) → the compact column runs past the stage crop, so the stage cuts it.
- Square highlight in compact (the column clip cut the row's rounded fill) → the compact column's clip reaches the Panel edge.
- Cursor over the excerpt on click → aims at the row's lower padding.
- `settle snap` / `jump` of 120px on `ss-count__strip` (candidates, not gate lines) → this is `Count` putting its digit strip back on its middle decade after a roll. A zoom at 60 ms (`countdown-zoom.png`) shows the digits rolling and landing cleanly with no visible hop. Left as is.
- `appears with no entrance` on a column count at 390 (candidate) → the first frame of the page load; not a story beat.
- Coverage was marked `inconclusive` on some runs because of sampling gaps on a loaded machine (largest gap about 40 ms).

## Bento

Gold: `examples/bento` (Kite). Kept: the tile frame, run-in copy, one Stage per picture measured to the tile, `play="once"` beats staggered 110 ms, the dark stat tile, container-query layouts (3, 2 and 1 columns).

| Tile | Span | Kind | The one thing | Moves |
|---|---|---|---|---|
| Alerts | 2 x 1 | Hero UI | DMs and Mentions Alert settings (Sound, Alert sound, Shake, Ignore Focus) | Shake for Mentions turns on |
| Speed | 1 x 1 | Stat | "60 s" | counts up to 60 |
| Sources | 1 x 1 | Diagram | Slack, Gmail and Google Calendar marks (kit `BrandMark`) into the Panel | the lines draw in |
| Private | 1 x 1 | Statement | "Hidden from screen sharing." | holds still |
| Join | 1 x 1 | Component | An Event starting now, Google Meet mark, Join | Join presses |

Checks: there's no window chrome in the grid (the hero above already shows the Panel). No mark or real string repeats from one tile to another or from the hero. Neighbours differ in kind across and down.

Gate (1280 and 390, light and dark): all four ended `rehearsal passed (necessary, not sufficient: ...)`.

Film lines fixed: `fat row` (settings rows reduced to 42px), `uneven gutters` (the settings pane and its groups now run off the tile's bottom; the Join card sits one gutter from the bottom), `lopsided` (source pills hug their labels).

## How to film again

Filming is a local step only. It isn't part of the site's dependencies or of CI. From a clone of the Stageshow skill, with its `npm install` done (which brings `playwright-core`), and Chrome installed:

```sh
# in site/
npm run dev -- --port 5192
# in the skill clone
node scripts/film.mjs "http://127.0.0.1:5192/" --select ".pg-hero-demo" --width 1280 --every 700 --count 20 --gate --out shots/hero.png
node scripts/film.mjs "http://127.0.0.1:5192/" --select ".pg-hero-demo" --width 390 --every 700 --count 20 --gate --out shots/hero-390.png
node scripts/film.mjs "http://127.0.0.1:5192/" --select ".nw-bento" --width 1280 --every 400 --count 8 --gate --out shots/bento.png
```

Add `--dark` for the dark look and `--reduced --still` for the poster. `CHROME_PATH` picks another Chrome.

## Review

The fresh-eye review in `references/review.md` (a separate reviewer with only the frames) was not run. The builder answered the `verify.md` questions from the frames instead, and that's weaker.

## Assumptions

- People, messages, Events and Emails are invented. Times fit a 09:18 "now" on Tuesday 17 November.
- "Alert sound" stands in for the Settings picker that is labelled "Sound" in the app, so it isn't confused with the Sound switch above it.
- The page is shown at 1:1 from a 1168px viewport. Between 640 and 1168 the wide hero scales down: text reaches about 10px at 800 wide.

## Unresolved

- Between about 640 and 800px wide, the scaled wide hero has small type. A middle design wasn't built.

## Not checked

- Safari and Firefox rendering (backdrop-filter, `text-box`), real touch devices, and a hidden-tab or offscreen resume on a real page. All filming was in headless Chrome.
- 1:1 frame-rate pacing on a real display (the virtual clock proves geometry only).
- Widths between 390 and 1280 other than by full-page screenshots at 390 and 1280.
