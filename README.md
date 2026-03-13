# meetR

An open-source, when2meet-style group scheduling tool for R users. Provide a CSV of proposed dates and hours, authenticate with Google Sheets, and meetR launches a shareable Shiny app that collects and visualises group availability in real time.

## How it works

1. **Organiser** creates a Google Sheet, calls `meetr_auth()` + `meetr_setup()`, then runs `meetr_launch()` with a local CSV file.
2. meetR saves the event to Google Sheets and launches (or deploys) a Shiny app.
3. **Respondents** visit the app URL, enter their name, and click/drag on the time grid to mark when they are free.
4. The heatmap updates live as responses come in.

## Installation

```r
# Install from GitHub
remotes::install_github("kartik0trivedi/meetR")
```

## Quick start

### 1. Create a Google Sheet

Go to [sheets.google.com](https://sheets.google.com) and create a blank spreadsheet. Copy the Sheet ID from the URL:

```
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

| column    | format         | description                           |
| --------- | -------------- | ------------------------------------- |
| `date`  | `YYYY-MM-DD` | date of the slot                      |
| `start` | integer 0–23  | start hour (24-hour clock)            |
| `end`   | integer 1–24  | end hour (exclusive, must be > start) |

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
# Run locally
meetr_launch(sample_csv, event_name = "Team Sync Q2")

# Deploy to shinyapps.io and share the URL
meetr_launch(sample_csv, event_name = "Team Sync Q2", deploy = TRUE)
```

## Functions

| function                               | description                                                                                                                                     |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `meetr_auth(sheet_id, path)`         | Authenticate with Google Sheets and store the Sheet ID for the session. Pass `path` for a service account JSON (recommended for deployments). |
| `meetr_setup(sheet_id)`              | Initialise the Google Sheet with `events` and `responses` tabs. Run once after creating the sheet.                                          |
| `meetr_launch(csv, event_name, ...)` | Parse the CSV, save the event, and run or deploy the Shiny app.                                                                                 |

## Service account authentication (recommended for deployment)

For shinyapps.io deployments, use a Google service account instead of interactive OAuth:

1. Create a service account in [Google Cloud Console](https://console.cloud.google.com) and download the JSON key.
2. Share your Google Sheet with the service account email (Editor access).
3. Pass the path to `meetr_auth()`:

```r
meetr_auth("YOUR_SHEET_ID", path = "path/to/service-account.json")
meetr_launch("availability.csv", event_name = "My Event", deploy = TRUE)
```

## Shiny app features

- Click or drag to select/deselect time slots
- Previous submissions are pre-filled when a returning respondent types their name
- Participant list shown in the sidebar
- Live group availability heatmap (ggplot2)

## Dependencies

**Required:** dplyr, googlesheets4, shiny, tidyr

**Suggested (used in the Shiny app):** ggplot2, lubridate, rsconnect

## License

MIT
