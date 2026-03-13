# Internal Google Sheets I/O functions -- not exported.

# Suppress R CMD check NOTEs for dplyr column names used in pipes
utils::globalVariables(c(
  "slots", "slot_list", "slot", "user_name", "submitted_at"
))

.save_event <- function(sheet_id, event_id, event_name, slots) {
  googlesheets4::sheet_append(
    sheet_id,
    data.frame(
      event_id   = event_id,
      event_name = event_name,
      slots      = paste(slots, collapse = ","),
      created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
      stringsAsFactors = FALSE
    ),
    sheet = "events"
  )
}

.save_response <- function(sheet_id, event_id, user_name, selected_slots) {
  googlesheets4::sheet_append(
    sheet_id,
    data.frame(
      event_id     = event_id,
      user_name    = user_name,
      slots        = paste(selected_slots, collapse = ","),
      submitted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
      stringsAsFactors = FALSE
    ),
    sheet = "responses"
  )
}

.get_event <- function(sheet_id, event_id) {
  df <- tryCatch(
    googlesheets4::read_sheet(sheet_id, sheet = "events", col_types = "c"),
    error = function(e) {
      message("meetR: could not read events sheet - ", e$message)
      NULL
    }
  )
  if (is.null(df) || nrow(df) == 0) return(NULL)
  row <- df[df$event_id == event_id, ]
  if (nrow(row) == 0) NULL else row[1, ]
}

# Returns one row per user -- latest submission wins
.get_responses <- function(sheet_id, event_id) {
  empty <- data.frame(
    event_id = character(), user_name = character(),
    slots = character(), submitted_at = character(),
    stringsAsFactors = FALSE
  )
  df <- tryCatch(
    googlesheets4::read_sheet(sheet_id, sheet = "responses", col_types = "c"),
    error = function(e) {
      message("meetR: could not read responses sheet - ", e$message)
      NULL
    }
  )
  if (is.null(df) || nrow(df) == 0) return(empty)
  df |>
    dplyr::filter(event_id == !!event_id) |>
    dplyr::arrange(dplyr::desc(submitted_at)) |>
    dplyr::distinct(user_name, .keep_all = TRUE)
}

# Expand latest responses into per-slot counts
.compute_slot_counts <- function(resp_df) {
  empty <- data.frame(
    slot = character(), count = integer(), names = character(),
    stringsAsFactors = FALSE
  )
  if (nrow(resp_df) == 0) return(empty)
  resp_df |>
    dplyr::filter(!is.na(slots) & slots != "") |>
    dplyr::mutate(slot_list = strsplit(slots, ",")) |>
    tidyr::unnest(slot_list) |>
    dplyr::rename(slot = slot_list) |>
    dplyr::group_by(slot) |>
    dplyr::summarise(
      count = dplyr::n(),
      names = paste(user_name, collapse = ", "),
      .groups = "drop"
    )
}
