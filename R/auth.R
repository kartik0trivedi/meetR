#' Authenticate meetR with Google Sheets
#'
#' Call this once per session (or once ever if using a service account).
#' Stores the Sheet ID for use by [meetr_launch()].
#'
#' @param sheet_id The Google Sheets spreadsheet ID (the long string in the
#'   sheet URL). The sheet must have two tabs named `events` and `responses`.
#'   Run [meetr_setup()] to create them automatically.
#' @param path Optional path to a service account JSON file. Recommended for
#'   non-interactive / shinyapps.io deployments. If `NULL`, falls back to a
#'   cached OAuth token in `.secrets/`, or opens an interactive browser prompt.
#'
#' @return The `sheet_id` invisibly. Also sets the `MEETR_SHEET_ID`
#'   environment variable for the current session.
#'
#' @examples
#' \dontrun{
#' meetr_auth("1XjC2IZYfRuzTlJvsr-M8MU3hiwcAXwR00Sn08A3gU0A")
#' }
#'
#' @export
meetr_auth <- function(sheet_id, path = NULL) {
  if (!is.null(path)) {
    googlesheets4::gs4_auth(path = path)
  } else if (dir.exists(".secrets")) {
    googlesheets4::gs4_auth(cache = ".secrets", email = TRUE)
  } else {
    googlesheets4::gs4_auth()
  }

  Sys.setenv(MEETR_SHEET_ID = sheet_id)
  message("meetR: authenticated. Sheet ID stored for this session.")
  invisible(sheet_id)
}


#' Initialise the Google Sheet with the required tabs and headers
#'
#' Run once after creating a blank Google Sheet. Clears any existing content
#' in the `events` and `responses` tabs and writes the correct headers.
#'
#' @param sheet_id Google Sheets spreadsheet ID. Defaults to the value stored
#'   by [meetr_auth()].
#'
#' @return Invisible `NULL`.
#' @export
meetr_setup <- function(sheet_id = Sys.getenv("MEETR_SHEET_ID")) {
  .check_sheet_id(sheet_id)

  existing <- googlesheets4::sheet_names(sheet_id)

  for (tab in c("events", "responses")) {
    if (tab %in% existing) {
      message("meetR: clearing '", tab, "' tab...")
      googlesheets4::range_clear(sheet_id, sheet = tab, reformat = FALSE)
    } else {
      googlesheets4::sheet_add(sheet_id, sheet = tab)
      message("meetR: created '", tab, "' tab.")
    }
  }

  googlesheets4::range_write(
    sheet_id,
    data.frame(
      event_id   = character(),
      event_name = character(),
      slots      = character(),
      created_at = character()
    ),
    sheet = "events", range = "A1", col_names = TRUE, reformat = FALSE
  )

  googlesheets4::range_write(
    sheet_id,
    data.frame(
      event_id     = character(),
      user_name    = character(),
      slots        = character(),
      submitted_at = character()
    ),
    sheet = "responses", range = "A1", col_names = TRUE, reformat = FALSE
  )

  message("meetR: Google Sheet is ready.")
  invisible(NULL)
}


# Internal: stop early if sheet_id is missing
.check_sheet_id <- function(sheet_id) {
  if (is.null(sheet_id) || is.na(sheet_id) || nchar(trimws(sheet_id)) == 0) {
    stop(
      "No sheet_id provided. ",
      "Run meetr_auth(sheet_id = '...') first, or pass sheet_id explicitly.",
      call. = FALSE
    )
  }
}
