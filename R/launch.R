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
#' meetr_auth("1XjC2IZYfRuzTlJvsr-M8MU3hiwcAXwR00Sn08A3gU0A")
#'
#' # Use the bundled sample CSV as a starting point
#' sample_csv <- system.file("extdata", "sample_availability.csv", package = "meetR")
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
  app_title = "meetR",
  sheet_id  = Sys.getenv("MEETR_SHEET_ID"),
  deploy    = FALSE,
  app_name  = .slugify(app_title),
  ...
) {
  .check_sheet_id(sheet_id)

  if (!file.exists(csv)) {
    stop("CSV file not found: ", csv, call. = FALSE)
  }

  # 1. Parse the CSV
  message("meetR: parsing availability CSV...")
  result <- .parse_csv_slots(csv)
  if (!is.null(result$error)) stop(result$error, call. = FALSE)

  slots    <- result$slots
  n_slots  <- length(slots)
  n_dates  <- length(unique(substr(slots, 1, 10)))
  message("meetR: found ", n_slots, " slots across ", n_dates, " date(s).")

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

  # Copy cached OAuth token if present (for non-service-account auth)
  if (dir.exists(".secrets")) {
    file.copy(".secrets", deploy_dir, recursive = TRUE)
    message("meetR: bundling .secrets/ for deployment.")
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
