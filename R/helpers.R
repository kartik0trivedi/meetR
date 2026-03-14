# Internal helper functions — not exported.
# A duplicate of these lives in inst/shiny/helpers.R for the standalone app.

# ---- CSV parsing ---------------------------------------------------------

#' Parse organiser CSV into a vector of slot IDs
#'
#' @param filepath Path to the CSV file.
#' @return A list with either `$slots` (character vector) or `$error` (string).
#' @noRd
.parse_csv_slots <- function(filepath, granularity = 60L) {
  df <- tryCatch(
    utils::read.csv(filepath, stringsAsFactors = FALSE, strip.white = TRUE),
    error = function(e) NULL
  )
  if (is.null(df)) return(list(error = "Could not read the CSV file."))

  names(df) <- tolower(trimws(names(df)))

  missing_cols <- setdiff(c("date", "start", "end"), names(df))
  if (length(missing_cols) > 0) {
    return(list(error = paste(
      "CSV must have columns: date, start, end. Missing:",
      paste(missing_cols, collapse = ", ")
    )))
  }

  granularity  <- as.integer(granularity)
  mins_per_hour <- seq(0L, 59L, by = granularity)   # e.g. c(0,30) for 30-min

  slots  <- character(0)
  errors <- character(0)

  for (i in seq_len(nrow(df))) {
    d <- tryCatch(as.Date(df$date[i]), error = function(e) NA)
    if (is.na(d)) {
      errors <- c(errors, sprintf("Row %d: invalid date '%s'", i, df$date[i]))
      next
    }
    s <- suppressWarnings(as.integer(df$start[i]))
    e <- suppressWarnings(as.integer(df$end[i]))
    if (is.na(s) || is.na(e) || s >= e || s < 0L || e > 24L) {
      errors <- c(errors, sprintf(
        "Row %d: invalid hours %s\u2013%s (must be integers 0\u201324, start < end)",
        i, df$start[i], df$end[i]
      ))
      next
    }
    new_slots <- unlist(lapply(s:(e - 1L), function(h) {
      paste0(
        format(d, "%Y-%m-%d"), "_",
        sprintf("%02d", h), ":", sprintf("%02d", mins_per_hour)
      )
    }))
    slots <- c(slots, new_slots)
  }

  if (length(errors) > 0) return(list(error = paste(errors, collapse = "\n")))
  if (length(slots) == 0) return(list(error = "No valid time slots found."))

  list(slots = unique(slots))
}


# ---- Slot utilities ------------------------------------------------------

.slots_to_dates <- function(slots) {
  sort(unique(as.Date(substr(slots, 1, 10))))
}

.slots_to_hours <- function(slots) {
  sort(unique(as.integer(substr(slots, 12, 13))))
}

.format_hour <- function(h) {
  h <- as.integer(h)
  sprintf("%d %s", ifelse(h %% 12 == 0, 12, h %% 12), ifelse(h < 12, "AM", "PM"))
}

.format_slot_time <- function(h, m) {
  h  <- as.integer(h)
  m  <- as.integer(m)
  hh <- ifelse(h %% 12 == 0, 12L, h %% 12L)
  sprintf("%d:%02d %s", hh, m, ifelse(h < 12, "AM", "PM"))
}
