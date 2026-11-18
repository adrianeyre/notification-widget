// Draws the illustrated portraits of the invented people in the screenshots and the
// site's hero, as small SVGs in public/avatars/. They stand in for Slack profile photos
// and Gravatars, so the pictures show what the app looks like with real ones, without
// using anyone's real face. The app's Debug snapshots read the same files.
//
// Run from site/: node scripts/avatars.mjs

import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'public', 'avatars')

const SKIN = { light: '#f3d2b8', fair: '#eac09f', tan: '#d39b72', brown: '#a8714b', deep: '#7a4a2e' }
const HAIR = { black: '#2b2523', brown: '#5b3a29', auburn: '#8a4a2c', blond: '#d6b36a', grey: '#a7a2a0', dark: '#3b2b24' }

// Who appears where: the app's SampleItems (docs screenshots) and the site's hero.
// Anyone not listed (Payroll, GitHub, a group DM, and a couple of Email senders on the
// site) has no photo, so the pictures show the initials fallback too.
const PEOPLE = [
  { slug: 'priya-shah', skin: 'tan', hair: 'long', hairColor: 'black', shirt: '#4f7cac', bg: '#dfe9f3' },
  { slug: 'sam-lee', skin: 'fair', hair: 'short', hairColor: 'black', shirt: '#3d6b5a', bg: '#e1efe8', glasses: true },
  { slug: 'jordan-kim', skin: 'fair', hair: 'bob', hairColor: 'dark', shirt: '#b5654a', bg: '#f5e4dc' },
  { slug: 'alex-chen', skin: 'light', hair: 'wavy', hairColor: 'dark', shirt: '#6a5a9c', bg: '#e8e3f4' },
  { slug: 'robin-diaz', skin: 'brown', hair: 'curly', hairColor: 'black', shirt: '#c08a3e', bg: '#f4ecd9' },
  { slug: 'casey-wu', skin: 'light', hair: 'bun', hairColor: 'black', shirt: '#3f7f8c', bg: '#dceef0' },
  { slug: 'jamie-fox', skin: 'light', hair: 'short', hairColor: 'auburn', shirt: '#7a8794', bg: '#e6ebef', beard: true },
  { slug: 'tom-okafor', skin: 'deep', hair: 'buzz', hairColor: 'black', shirt: '#2f6f8f', bg: '#dbe9f1' },
  { slug: 'lena-fischer', skin: 'light', hair: 'long', hairColor: 'blond', shirt: '#a3536b', bg: '#f4e1e7' },
  { slug: 'sam-reid', skin: 'fair', hair: 'wavy', hairColor: 'brown', shirt: '#5a7d3c', bg: '#e6efdc', glasses: true },
  { slug: 'nina-haas', skin: 'light', hair: 'bob', hairColor: 'auburn', shirt: '#3c5a8f', bg: '#e0e6f3' },
  { slug: 'olu-adeyemi', skin: 'deep', hair: 'curly', hairColor: 'black', shirt: '#b06f2f', bg: '#f3e6d6', beard: true },
  { slug: 'maria-lopez', skin: 'tan', hair: 'wavy', hairColor: 'dark', shirt: '#8f3c5a', bg: '#f1dfe6' },
  { slug: 'aisha-khan', skin: 'brown', hair: 'bun', hairColor: 'black', shirt: '#2f7a6a', bg: '#dcefe9', glasses: true },
]

/** A colour `amount` (0–1) darker, for shading. */
function shade(hex, amount) {
  const n = parseInt(hex.slice(1), 16)
  const c = [n >> 16, (n >> 8) & 255, n & 255].map((v) => Math.round(v * (1 - amount)))
  return `#${c.map((v) => v.toString(16).padStart(2, '0')).join('')}`
}

// Hair behind the head (long styles) and on top of it, on a 128 × 128 face
// centred at (64, 60), radius about 23 × 27.
const BACK = {
  long: (c) => `<path d="M36 58c0-22 12-36 28-36s28 14 28 36v40H36z" fill="${c}"/>`,
  bob: (c) => `<path d="M37 60c0-22 11-35 27-35s27 13 27 35v18c0 4-3 6-6 6H43c-3 0-6-2-6-6z" fill="${c}"/>`,
  wavy: (c) => `<path d="M38 60c-2-22 10-36 26-36s28 14 26 36c3 8 1 16-4 22H42c-5-6-7-14-4-22z" fill="${c}"/>`,
}
const TOP = {
  short: (c) => `<path d="M40 56c-1-18 10-28 24-28s25 10 24 28c-4-9-12-13-24-13s-20 4-24 13z" fill="${c}"/>`,
  buzz: (c) => `<path d="M41 54c1-15 11-23 23-23s22 8 23 23c-6-6-14-9-23-9s-17 3-23 9z" fill="${c}"/>`,
  long: (c) => `<path d="M40 60c-2-20 9-32 24-32s26 12 24 32c-3-12-11-20-24-20 0 0-3 8-14 12-4 2-7 5-10 8z" fill="${c}"/>`,
  bob: (c) => `<path d="M40 60c-2-20 9-32 24-32s26 12 24 32c-5-10-12-15-24-15s-19 5-24 15z" fill="${c}"/>`,
  wavy: (c) => `<path d="M40 60c-3-20 9-33 24-33s27 13 24 33c-3-9-9-13-16-13-3 4-9 6-16 5-7 0-12 3-16 8z" fill="${c}"/>`,
  curly: (c) =>
    [[48, 38, 9], [60, 33, 10], [72, 34, 10], [82, 42, 9], [42, 48, 8], [86, 52, 7]]
      .map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}" fill="${c}"/>`)
      .join(''),
  bun: (c) =>
    `<circle cx="64" cy="24" r="10" fill="${c}"/><path d="M41 56c0-17 10-27 23-27s23 10 23 27c-5-8-13-12-23-12s-18 4-23 12z" fill="${c}"/>`,
}

function svg(p) {
  const skin = SKIN[p.skin]
  const hair = HAIR[p.hairColor]
  const back = BACK[p.hair]?.(hair) ?? ''
  const glasses = p.glasses
    ? `<g fill="none" stroke="#2d2a2a" stroke-width="2"><circle cx="55" cy="62" r="6"/><circle cx="73" cy="62" r="6"/><path d="M61 62h6"/></g>`
    : ''
  const beard = p.beard
    ? `<path d="M43 66c2 14 10 22 21 22s19-8 21-22c-4 6-9 8-12 8-3-3-6-3-9-3s-6 0-9 3c-3 0-8-2-12-8z" fill="${hair}"/>`
    : ''
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
<clipPath id="c"><circle cx="64" cy="64" r="64"/></clipPath>
<g clip-path="url(#c)">
<rect width="128" height="128" fill="${p.bg}"/>
${back}
<path d="M20 128c2-22 20-34 44-34s42 12 44 34z" fill="${p.shirt}"/>
<path d="M54 80h20v14c0 6-20 6-20 0z" fill="${shade(skin, 0.12)}"/>
<path d="M54 94c3 4 7 6 10 6s7-2 10-6l-4-3h-12z" fill="${shade(p.shirt, 0.18)}"/>
<ellipse cx="41" cy="62" rx="4" ry="6" fill="${shade(skin, 0.06)}"/>
<ellipse cx="87" cy="62" rx="4" ry="6" fill="${shade(skin, 0.06)}"/>
<ellipse cx="64" cy="60" rx="23" ry="27" fill="${skin}"/>
${beard}
${TOP[p.hair](hair)}
<circle cx="55" cy="62" r="2.4" fill="#2d2a2a"/>
<circle cx="73" cy="62" r="2.4" fill="#2d2a2a"/>
<path d="M57 73c4 4 10 4 14 0" fill="none" stroke="${shade(skin, 0.45)}" stroke-width="2.2" stroke-linecap="round"/>
${glasses}
</g>
</svg>
`
}

mkdirSync(out, { recursive: true })
for (const person of PEOPLE) writeFileSync(join(out, `${person.slug}.svg`), svg(person))
console.log(`Wrote ${PEOPLE.length} avatars to ${out}`)
