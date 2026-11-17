# v1 soak test

Issue #24. Run the app for **5 working days** and check it against the PRD §7 success criteria. Add a comment on #24 each day, and file anything that goes wrong as a new issue linked from #24.

## Before you start

- [ ] Build a signed Release build (with `Config/Secrets.xcconfig` filled in) and move it to `/Applications`.
- [ ] Google and Slack are connected in Settings → Accounts, and every Panel section is free of health indicators.
- [ ] Launch at login is on, and Focus permission is granted (Settings → Alerts → Focus).
- [ ] Sound and shake are on for every Source.

## Each day

| Check | Day 1 | Day 2 | Day 3 | Day 4 | Day 5 |
|---|---|---|---|---|---|
| Logged in: the app started by itself and Backfilled without Alerts | | | | | |
| A test DM appeared and Alerted within 60 s | | | | | |
| A test @mention appeared and Alerted within 60 s | | | | | |
| A test Email appeared and Alerted within 60 s | | | | | |
| Every Event Alerted at its Reminder Time (none missed) | | | | | |
| No restarts or manual reconnects needed (apart from sign-in expiry, which the health indicator showed) | | | | | |
| After sleep and wake, everything recovered by itself | | | | | |
| The Panel didn't appear in any screen share | | | | | |
| During a Focus, Items appeared without sound or shake | | | | | |

## Wrapping up

- [ ] All five criteria in PRD §7 held for the whole week.
- [ ] Every problem found has its own issue, linked from #24.
- [ ] Close #24.
