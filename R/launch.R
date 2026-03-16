#' Launch the meetR availability app
#'
#' Reads the organiser's availability CSV, saves the event to Google Sheets,
#' then either runs the Shiny app locally or deploys it to shinyapps.io.
#'
#' The CSV must have three columns:
#' \describe{
#'   \item{date}{Date in `YYYY-MM-DD` format.}
#'   \item{start}{Start hour (integer, 0–23, 24-hour clock).}
#'   \item{end}{End hour (integer, 1–24, exclusive). Must be > start.}
#' }
#' Multiple rows per date are allowed (e.g. morning + afternoon blocks).
#'
#' @param csv Path to the availability CSV file.
#' @param event_name Display name for the event shown to respondents.
#' @param app_title Title shown in the browser tab / app header.
#'   Defaults to `"meetR"`.
#' @param timezone An Olson timezone name (e.g. `"America/Chicago"`,
#'   `"Europe/London"`, `"UTC"`). Displayed in the app so respondents know
#'   which timezone the hours refer to. Defaults to the system timezone via
#'   `Sys.timezone()`.
#' @param granularity Slot duration in minutes. Must be `15`, `30`, or `60`
#'   (default). Controls how finely the time grid is divided — e.g. `30`
#'   produces half-hour blocks such as 9:00 AM, 9:30 AM, 10:00 AM.
#' @param expected_n Optional positive integer. The total number of people the
#'   organiser expects to respond. When set, the app shows a progress bar and
#'   "X / N responded" counter in the participants panel so respondents know
#'   how many others are expected.
#' @param sheet_id Google Sheets spreadsheet ID. Defaults to the value stored
#'   by [meetr_auth()].
#' @param deploy If `TRUE`, deploy the app to shinyapps.io instead of running
#'   locally. Requires the \pkg{rsconnect} package to be configured.
#' @param app_name shinyapps.io app name (used when `deploy = TRUE`).
#'   Defaults to a slugified version of `app_title`.
#' @param ... Additional arguments passed to `shiny::runApp()` (when
#'   `deploy = FALSE`) or `rsconnect::deployApp()` (when `deploy = TRUE`).
#'
#' @return Invisible `NULL`. Called for its side effects.
#'
#' @examples
#' \dontrun{
#' meetr_auth("YOUR_SHEET_ID")
#'
#' # Use the bundled sample CSV as a starting point
#' sample_csv <- system.file(
#'   "extdata", "sample_availability.csv", package = "meetR"
#' )
#'
#' # Run locally
#' meetr_launch(sample_csv, event_name = "Team Sync Q2")
#'
#' # Deploy to shinyapps.io
#' meetr_launch(sample_csv, event_name = "Team Sync Q2", deploy = TRUE)
#' }
#'
#' @export
meetr_launch <- function(
  csv,
  event_name,
  app_title   = "meetR",
  timezone    = Sys.timezone(),
  granularity = 60L,
  expected_n  = NULL,
  sheet_id    = Sys.getenv("MEETR_SHEET_ID"),
  deploy      = FALSE,
  app_name    = .slugify(app_title),
  ...
) {
  .check_sheet_id(sheet_id)

  if (!timezone %in% OlsonNames()) {
    stop(
      "'", timezone, "' is not a recognised timezone. ",
      "See OlsonNames() for valid values.",
      call. = FALSE
    )
  }

  granularity <- as.integer(granularity)
  if (!granularity %in% c(15L, 30L, 60L)) {
    stop("'granularity' must be 15, 30, or 60.", call. = FALSE)
  }

  if (!is.null(expected_n)) {
    expected_n <- as.integer(expected_n)
    if (is.na(expected_n) || expected_n < 1L) {
      stop("'expected_n' must be a positive integer.", call. = FALSE)
    }
  }

  if (!file.exists(csv)) {
    stop("CSV file not found: ", csv, call. = FALSE)
  }

  # 1. Parse the CSV
  message("meetR: parsing availability CSV...")
  result <- .parse_csv_slots(csv, granularity = granularity)
  if (!is.null(result$error)) stop(result$error, call. = FALSE)

  slots    <- result$slots
  n_slots  <- length(slots)
  n_dates  <- length(unique(substr(slots, 1, 10)))
  message("meetR: found ", n_slots, " slot(s) across ", n_dates,
          " date(s) (", granularity, "-min blocks).")

  # 2. Save event to Google Sheets
  message("meetR: saving event to Google Sheets...")
  event_id <- .generate_event_id()
  .save_event(sheet_id, event_id, event_name, slots)
  message("meetR: event saved (id: ", event_id, ").")

  # 3. Build the app config
  config <- list(
    sheet_id   = sheet_id,
    event_id   = event_id,
    event_name = event_name,
    app_title  = app_title,
    timezone   = timezone,
    expected_n = expected_n,
    slots      = slots
  )

  if (deploy) {
    .deploy_app(config, app_name, ...)
  } else {
    .run_app_local(config, ...)
  }

  invisible(NULL)
}


# ---- Internal launchers --------------------------------------------------

.run_app_local <- function(config, ...) {
  app_dir <- system.file("shiny", package = "meetR")
  saveRDS(config, file.path(app_dir, "config.rds"))
  message("meetR: launching app locally...")
  shiny::runApp(app_dir, ...)
}

.deploy_app <- function(config, app_name, ...) {
  if (!requireNamespace("rsconnect", quietly = TRUE)) {
    stop(
      "Package 'rsconnect' is required for deployment. ",
      "Install it with: install.packages('rsconnect')",
      call. = FALSE
    )
  }

  # Build a self-contained deploy bundle in a temp directory
  deploy_dir <- tempfile("meetR_deploy_")
  dir.create(deploy_dir)
  on.exit(unlink(deploy_dir, recursive = TRUE), add = TRUE)

  # Copy app files from inst/shiny/
  inst_dir <- system.file("shiny", package = "meetR")
  file.copy(
    list.files(inst_dir, full.names = TRUE),
    deploy_dir,
    recursive = TRUE
  )

  # Write config
  saveRDS(config, file.path(deploy_dir, "config.rds"))

  # Bundle service account JSON if one was used in meetr_auth()
  creds_path <- Sys.getenv("MEETR_CREDENTIALS_PATH")
  if (nchar(creds_path) > 0 && file.exists(creds_path)) {
    file.copy(creds_path, file.path(deploy_dir, "credentials.json"))
    message("meetR: bundling service account credentials for deployment.")
  } else if (dir.exists(".secrets")) {
    # Fallback: cached OAuth token
    file.copy(".secrets", deploy_dir, recursive = TRUE)
    message("meetR: bundling .secrets/ for deployment.")
  } else {
    warning(
      "meetR: no credentials found to bundle. ",
      "The deployed app may fail to authenticate with Google Sheets. ",
      "Call meetr_auth(sheet_id, path = 'service-account.json') before",
      " deploying.",
      call. = FALSE
    )
  }

  message("meetR: deploying to shinyapps.io as '", app_name, "'...")
  rsconnect::deployApp(
    appDir  = deploy_dir,
    appName = app_name,
    ...
  )
}


# ---- Internal utilities --------------------------------------------------

.slugify <- function(x) {
  tolower(gsub("[^a-zA-Z0-9]+", "-", trimws(x)))
}

.generate_event_id <- function() {
  paste0(sample(c(letters, 0:9), 8, replace = TRUE), collapse = "")
}
