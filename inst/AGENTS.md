# meetR — Agent Instructions

meetR is an R package that turns an availability CSV into a shareable Shiny scheduling app backed by Google Sheets. This file tells you everything you need to go from a scheduling request to a live app URL.

The input can be anything: a pasted email thread, a Slack message, a forwarded calendar invite, or a plain prompt such as *"schedule a 1-hour meeting for next week, mornings only, three people — two on the US East Coast and one in Paris"*. Parse whatever the user gives you.

---

## End-to-end workflow

### 1. Parse the request

Extract from the user's message or prompt:

- **Proposed dates** — specific dates or a date range (e.g. "week of June 15")
- **Available hours** — stated as clock hours or implied by timezone overlap
- **Timezones** — infer from locations ("East Coast" → `America/New_York`, "European time" → `Europe/Paris`, "Hong Kong" → `Asia/Hong_Kong`)
- **Respondents** — count them to set `expected_n`
- **Constraints** — "available after June 15", "mornings only", "not Friday", etc.

When multiple timezones are involved, find the overlap window and express it in the **organizer's timezone**. The app lets each respondent view times in their own timezone — you do not need to convert slot hours per person.

### 2. Write the availability CSV

Create a file (e.g. `availability.csv`) with exactly three columns:

```csv
date,start,end
2026-06-15,9,13
2026-06-16,9,13
```

| column | format | notes |
| --- | --- | --- |
| `date` | `YYYY-MM-DD` | one row per contiguous block per day |
| `start` | integer 0–23 | start hour, 24-hour clock, inclusive |
| `end` | integer 1–24 | end hour, exclusive, must be > start |

Multiple rows per date are allowed for non-contiguous blocks (e.g. morning + afternoon). The CSV must be saved to disk before calling `meetr_launch()`.

**Timezone overlap guidance:**

- East Coast (EDT) is UTC−4, Western Europe (CEST) is UTC+2 → 6-hour gap
- A 9 AM–1 PM ET window = 3–7 PM CEST: comfortable for both sides
- Use that kind of reasoning to pick `start`/`end` values

### 3. Authenticate

```r
library(meetR)

meetr_auth(
  "YOUR_SHEET_ID",
  path = "path/to/service-account.json"  # omit for interactive OAuth
)
```

The Sheet ID is the long string in the Google Sheets URL:
`https://docs.google.com/spreadsheets/d/<SHEET_ID>/edit`

If the sheet has never been used with meetR, run once:

```r
meetr_setup()  # creates 'events' and 'responses' tabs
```

### 4. Launch

```r
meetr_launch(
  "availability.csv",
  event_name  = "Team Sync — June 2026",   # shown to respondents
  app_title   = "meetR",                    # browser tab title
  timezone    = "America/New_York",         # organizer's Olson timezone
  granularity = 60L,                        # 15, 30, or 60 minutes
  expected_n  = 3L,                         # optional: shows progress bar
  deploy      = TRUE,                       # FALSE to run locally
  app_name    = "team-sync",                # shinyapps.io app name
  forceUpdate = TRUE                        # required when redeploying to same app name
)
```

Running locally (`deploy = FALSE`) opens the app in a browser immediately — useful for previewing before sharing.

---

## Key parameters

| parameter | default | when to set |
| --- | --- | --- |
| `csv` | required | path to the availability CSV |
| `event_name` | required | display name shown to respondents |
| `timezone` | `Sys.timezone()` | always set explicitly — use organizer's Olson name |
| `granularity` | `60` | `30` for half-hour slots, `15` for quarter-hour |
| `expected_n` | `NULL` | set to the number of people expected to respond |
| `deploy` | `FALSE` | `TRUE` to publish to shinyapps.io |
| `app_name` | slugified title | shinyapps.io app name; keep it short and stable |
| `forceUpdate` | — | pass `forceUpdate = TRUE` when redeploying to an existing app |

---

## Critical: do not re-run `meetr_launch()` on a live event

Every call to `meetr_launch()` generates a new `event_id` and writes a new event row to Google Sheets. **If you re-run it after responses have been collected, the app will point to the new event and existing responses will be invisible** (they are not deleted, just orphaned).

**For UI-only changes on a live event, deploy directly:**

```r
library(rsconnect)
library(meetR)

# Re-authenticate
meetr_auth("YOUR_SHEET_ID", path = "path/to/service-account.json")

# Rebuild the slot list from the original CSV
slots <- meetR:::.parse_csv_slots("availability.csv", granularity = 60L)$slots

# Reconstruct config with the ORIGINAL event_id (check config.rds or the Sheet)
config <- list(
  sheet_id   = "YOUR_SHEET_ID",
  event_id   = "ORIGINAL_EVENT_ID",   # <-- preserve this
  event_name = "Team Sync — June 2026",
  app_title  = "meetR",
  timezone   = "America/New_York",
  expected_n = 3L,
  slots      = slots
)

# Build and deploy
inst_dir   <- system.file("shiny", package = "meetR")
deploy_dir <- tempfile("meetR_deploy_")
dir.create(deploy_dir)
file.copy(list.files(inst_dir, full.names = TRUE), deploy_dir, recursive = TRUE)
saveRDS(config, file.path(deploy_dir, "config.rds"))
file.copy("path/to/service-account.json", file.path(deploy_dir, "credentials.json"))

rsconnect::deployApp(appDir = deploy_dir, appName = "team-sync", forceUpdate = TRUE)
```

The `event_id` is printed to the console when `meetr_launch()` runs (`meetR: event saved (id: xxxxxx)`). Save it.

---

## Respondent experience (3-step wizard)

1. **Step 1 — Your Info:** name + timezone selector
2. **Step 2 — Select Times:** click/drag grid; times displayed in chosen timezone; returning users are pre-filled
3. **Step 3 — Confirm & Save:** day-by-day summary before submitting

Submissions are stored in organizer timezone regardless of what the respondent selects for display.

---

## Typical agent session

```text
User: [pastes email, message, or describes availability in plain text]

Agent actions:
1. Identify dates, hours, timezones, respondent count from the input
2. Compute overlap window in organizer timezone
3. Write availability.csv
4. Call meetr_auth() + meetr_launch()
5. Return the app URL and the event_id (save it for future redeployments)
```

---

## Common Olson timezone names

| location | timezone |
| --- | --- |
| US East Coast | `America/New_York` |
| US Central | `America/Chicago` |
| US West Coast | `America/Los_Angeles` |
| UK | `Europe/London` |
| Western Europe | `Europe/Paris` or `Europe/Berlin` |
| India | `Asia/Kolkata` |
| Hong Kong / Singapore | `Asia/Hong_Kong` / `Asia/Singapore` |
| Japan / Korea | `Asia/Tokyo` / `Asia/Seoul` |
| UTC | `UTC` |
