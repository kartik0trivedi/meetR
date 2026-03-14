# Standalone helpers for inst/shiny/app.R
# These mirror R/helpers.R and R/sheets.R but have no dependency on the
# meetR package itself, so the deployed app works on shinyapps.io.

# ---- Slot utilities ------------------------------------------------------

slots_to_dates <- function(slots) {
  sort(unique(as.Date(substr(slots, 1, 10))))
}

slots_to_hours <- function(slots) {
  sort(unique(as.integer(substr(slots, 12, 13))))
}

# Format a time given hour h (0-23) and minute m (0-59) as "9:30 AM" etc.
format_slot_time <- function(h, m) {
  h  <- as.integer(h)
  m  <- as.integer(m)
  hh <- ifelse(h %% 12 == 0, 12L, h %% 12L)
  sprintf("%d:%02d %s", hh, m, ifelse(h < 12, "AM", "PM"))
}

# Convert original slot IDs (organizer TZ) to display positions in to_tz.
# Slot IDs use the format "YYYY-MM-DD_HH:MM".
# Returns a data frame: original_slot, display_date, display_hour, display_min.
# The grid uses display_date/display_hour/display_min for layout; data-slot
# keeps original_slot so submissions are always stored in organizer TZ
# without any server-side remapping.
slots_in_tz <- function(slots, from_tz, to_tz) {
  if (length(slots) == 0) {
    return(data.frame(
      original_slot = character(),
      display_date  = as.Date(character()),
      display_hour  = integer(),
      display_min   = integer(),
      stringsAsFactors = FALSE
    ))
  }
  if (identical(from_tz, to_tz)) {
    return(data.frame(
      original_slot = slots,
      display_date  = as.Date(substr(slots, 1, 10)),
      display_hour  = as.integer(substr(slots, 12, 13)),
      display_min   = as.integer(substr(slots, 15, 16)),
      stringsAsFactors = FALSE
    ))
  }
  # "YYYY-MM-DD_HH:MM" → "YYYY-MM-DD HH:MM:00"
  dt     <- as.POSIXct(
    paste0(substr(slots, 1, 10), " ", substr(slots, 12, 16), ":00"),
    tz = from_tz
  )
  dt_str <- format(dt, tz = to_tz, usetz = FALSE)  # "YYYY-MM-DD HH:MM:SS"
  data.frame(
    original_slot = slots,
    display_date  = as.Date(substr(dt_str, 1, 10)),
    display_hour  = as.integer(substr(dt_str, 12, 13)),
    display_min   = as.integer(substr(dt_str, 15, 16)),
    stringsAsFactors = FALSE
  )
}

# ---- Google Sheets I/O ---------------------------------------------------

save_response <- function(sheet_id, event_id, user_name, selected_slots) {
  googlesheets4::sheet_append(
    sheet_id,
    data.frame(
      event_id     = event_id,
      user_name    = user_name,
      slots        = paste(selected_slots, collapse = ","),
      submitted_at = format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
      stringsAsFactors = FALSE
    ),
    sheet = "responses"
  )
}

get_responses <- function(sheet_id, event_id) {
  empty <- data.frame(
    event_id = character(), user_name = character(),
    slots = character(), submitted_at = character(),
    stringsAsFactors = FALSE
  )
  df <- tryCatch(
    googlesheets4::read_sheet(sheet_id, sheet = "responses", col_types = "c"),
    error = function(e) { message("GSheets read error: ", e$message); NULL }
  )
  if (is.null(df) || nrow(df) == 0) return(empty)
  df <- df[df$event_id == event_id, ]
  if (nrow(df) == 0) return(empty)
  # Latest submission per user wins
  df <- df[order(df$submitted_at, decreasing = TRUE), ]
  df[!duplicated(df$user_name), ]
}

compute_slot_counts <- function(resp_df) {
  empty <- data.frame(
    slot = character(), count = integer(), names = character(),
    stringsAsFactors = FALSE
  )
  if (nrow(resp_df) == 0) return(empty)
  rows <- resp_df[!is.na(resp_df$slots) & resp_df$slots != "", ]
  if (nrow(rows) == 0) return(empty)

  expanded <- do.call(rbind, lapply(seq_len(nrow(rows)), function(i) {
    sl <- unlist(strsplit(rows$slots[i], ","))
    data.frame(user_name = rows$user_name[i], slot = sl,
               stringsAsFactors = FALSE)
  }))

  counts <- aggregate(user_name ~ slot, data = expanded, FUN = length)
  names(counts)[2] <- "count"
  nms    <- aggregate(user_name ~ slot, data = expanded,
                      FUN = function(x) paste(x, collapse = ", "))
  names(nms)[2] <- "names"
  merge(counts, nms, by = "slot")
}

# ---- Grid builder --------------------------------------------------------

build_grid <- function(slot_map, slot_counts_df, n_users) {
  dates <- sort(unique(slot_map$display_date))

  times     <- unique(slot_map[, c("display_hour", "display_min")])
  times     <- times[order(times$display_hour, times$display_min), ]
  row.names(times) <- NULL

  slot_map$disp_key <- paste0(
    format(slot_map$display_date, "%Y-%m-%d"), "_",
    sprintf("%02d", slot_map$display_hour), ":",
    sprintf("%02d", slot_map$display_min)
  )
  slot_lookup  <- stats::setNames(slot_map$original_slot, slot_map$disp_key)
  count_lookup <- stats::setNames(slot_counts_df$count,   slot_counts_df$slot)
  name_lookup  <- stats::setNames(slot_counts_df$names,   slot_counts_df$slot)

  header_cells <- shiny::tagList(
    shiny::tags$th("", style = "background:#f8f9fa; padding:6px 10px;"),
    lapply(dates, function(d) {
      shiny::tags$th(
        shiny::HTML(paste0(
          "<span>", format(d, "%a"), "</span>",
          "<br/><small>", format(d, "%m/%d"), "</small>"
        )),
        style = "min-width:65px; text-align:center; background:#f8f9fa; padding:6px;"
      )
    })
  )

  body_rows <- lapply(seq_len(nrow(times)), function(ri) {
    h <- times$display_hour[ri]
    m <- times$display_min[ri]
    cells <- shiny::tagList(
      shiny::tags$td(
        format_slot_time(h, m),
        style = paste0(
          "font-size:0.82em; color:#6c757d; text-align:right; padding:2px 8px;",
          " white-space:nowrap; background:#f8f9fa; border-right:2px solid #dee2e6;"
        )
      ),
      lapply(dates, function(d) {
        disp_key  <- paste0(format(d, "%Y-%m-%d"), "_",
                            sprintf("%02d", h), ":", sprintf("%02d", m))
        orig_slot <- slot_lookup[disp_key]
        is_valid  <- !is.na(orig_slot)

        if (!is_valid) {
          return(shiny::tags$td(style = paste0(
            "background:#ececec; width:60px; height:28px;",
            " border:1px solid #dee2e6; cursor:not-allowed;"
          )))
        }

        cnt <- count_lookup[orig_slot]
        if (is.null(cnt) || is.na(cnt)) cnt <- 0L
        pct <- cnt / max(n_users, 1)

        bg <- if (cnt == 0L) {
          "#ffffff"
        } else {
          r <- round(248 - pct * (248 - 46))
          g <- round(249 - pct * (249 - 125))
          b <- round(250 - pct * (250 - 50))
          sprintf("rgb(%d,%d,%d)", r, g, b)
        }

        tooltip <- name_lookup[orig_slot]
        if (is.null(tooltip) || is.na(tooltip)) tooltip <- ""

        label <- if (cnt > 0L) {
          shiny::tags$span(
            cnt,
            style = "font-size:0.75em; font-weight:700; color:rgba(255,255,255,0.9); pointer-events:none;"
          )
        } else NULL

        shiny::tags$td(
          class       = "slot-cell",
          `data-slot` = orig_slot,
          title       = tooltip,
          style       = paste0(
            "background-color:", bg, "; cursor:pointer;",
            " width:60px; height:28px; text-align:center;",
            " vertical-align:middle; border:1px solid #dee2e6;"
          ),
          label
        )
      })
    )
    shiny::tags$tr(cells)
  })

  shiny::tags$table(
    id    = "availability-grid",
    style = "border-collapse:collapse; user-select:none; -webkit-user-select:none;",
    shiny::tags$thead(shiny::tags$tr(header_cells)),
    shiny::tags$tbody(body_rows)
  )
}
