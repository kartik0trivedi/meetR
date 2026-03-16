# meetR

An open-source, when2meet-style group scheduling tool for R users. Provide a CSV of proposed dates and hours, authenticate with Google Sheets, and meetR launches a shareable Shiny app that collects and visualises group availability in real time.

## How it works

1. **Organiser** creates a Google Sheet, calls `meetr_auth()` + `meetr_setup()`, then runs `meetr_launch()` with a local CSV file.
2. meetR saves the event to Google Sheets and launches (or deploys) a Shiny app.
3. **Respondents** visit the app URL, enter their name, pick their preferred timezone, and click/drag on the time grid to mark when they are free.
4. The heatmap updates live as responses come in.

## Installation

```r
remotes::install_github("kartik0trivedi/meetR")
```

## Quick start

### 1. Create a Google Sheet

Go to [sheets.google.com](https://sheets.google.com) and create a blank spreadsheet. Copy the Sheet ID from the URL:

```text
https://docs.google.com/spreadsheets/d/<SHEET_ID>/edit
```

### 2. Authenticate and initialise

```r
library(meetR)

meetr_auth("YOUR_SHEET_ID")   # opens browser for OAuth on first run
meetr_setup()                  # creates 'events' and 'responses' tabs
```

### 3. Create your availability CSV

The CSV must have three columns:

| column | format | description |
| --- | --- | --- |
| `date` | `YYYY-MM-DD` | date of the slot |
| `start` | integer 0–23 | start hour (24-hour clock) |
| `end` | integer 1–24 | end hour (exclusive, must be > start) |

Multiple rows per date are allowed for non-contiguous blocks (e.g. morning + afternoon).

```csv
date,start,end
2026-03-16,9,12
2026-03-16,14,17
2026-03-17,9,17
2026-03-18,10,12
2026-03-18,15,18
```

A sample file is bundled with the package:

```r
sample_csv <- system.file("extdata", "sample_availability.csv", package = "meetR")
```

### 4. Launch

```r
# Run locally (hourly blocks, system timezone)
meetr_launch(sample_csv, event_name = "Team Sync Q2")

# 30-minute blocks, explicit timezone, expect 8 respondents
meetr_launch(
  sample_csv,
  event_name  = "Team Sync Q2",
  timezone    = "America/New_York",
  granularity = 30,
  expected_n  = 8
)

# Deploy to shinyapps.io and share the URL
meetr_launch(
  sample_csv,
  event_name  = "Team Sync Q2",
  timezone    = "America/New_York",
  granularity = 30,
  expected_n  = 8,
  deploy      = TRUE,
  app_name    = "team-sync"
)
```

## `meetr_launch()` parameters

| parameter | default | description |
| --- | --- | --- |
| `csv` | — | Path to the availability CSV file. |
| `event_name` | — | Display name for the event shown to respondents. |
| `app_title` | `"meetR"` | Title shown in the browser tab and app header. |
| `timezone` | `Sys.timezone()` | Olson timezone name (e.g. `"America/Chicago"`). Displayed in the app; respondents can also view times in their own timezone. |
| `granularity` | `60` | Slot duration in minutes. Must be `15`, `30`, or `60`. |
| `expected_n` | `NULL` | Expected total respondents. When set, shows a live progress bar (`X / N responded`) in the app. |
| `sheet_id` | `MEETR_SHEET_ID` env var | Google Sheets spreadsheet ID. |
| `deploy` | `FALSE` | If `TRUE`, deploy to shinyapps.io instead of running locally. |
| `app_name` | slugified title | shinyapps.io app name (used when `deploy = TRUE`). |

## Functions

| function | description |
| --- | --- |
| `meetr_auth(sheet_id, path)` | Authenticate with Google Sheets. Pass `path` for a service account JSON (recommended for deployments). |
| `meetr_setup(sheet_id)` | Initialise the Google Sheet with `events` and `responses` tabs. Run once after creating the sheet. |
| `meetr_launch(csv, event_name, ...)` | Parse the CSV, save the event, and run or deploy the Shiny app. |

## Service account authentication (recommended for deployment)

For shinyapps.io deployments, use a Google service account instead of interactive OAuth:

1. Create a service account in [Google Cloud Console](https://console.cloud.google.com) and download the JSON key.
2. Share your Google Sheet with the service account email (Editor access).
3. Pass the path to `meetr_auth()`:

```r
meetr_auth("YOUR_SHEET_ID", path = "path/to/service-account.json")
meetr_launch("availability.csv", event_name = "My Event", deploy = TRUE)
```

The credentials are automatically bundled into the deployment so the live app can authenticate without user interaction.

## Shiny app features

- Click or drag to select/deselect time slots
- **Timezone selector** — respondents can view and mark times in their own timezone; submissions are stored in the organiser's timezone
- **Progress bar** — shows `X / N responded` when `expected_n` is set
- Previous submissions are pre-filled when a returning respondent types their name
- Live group availability heatmap (ggplot2)

## Dependencies

**Required:** dplyr, googlesheets4, shiny, tidyr

**Suggested (used in the Shiny app):** ggplot2, rsconnect

## License

MIT
