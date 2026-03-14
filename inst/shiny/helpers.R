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

format_hour <- function(h) {
  h <- as.integer(h)
  sprintf("%d %s", ifelse(h %% 12 == 0, 12, h %% 12), ifelse(h < 12, "AM", "PM"))
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

build_grid <- function(dates, hours, valid_slots, slot_counts_df, n_users) {
  count_lookup <- stats::setNames(slot_counts_df$count, slot_counts_df$slot)
  name_lookup  <- stats::setNames(slot_counts_df$names, slot_counts_df$slot)
  valid_set    <- as.character(valid_slots)

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

  body_rows <- lapply(hours, function(h) {
    cells <- shiny::tagList(
      shiny::tags$td(
        format_hour(h),
        style = paste0(
          "font-size:0.82em; color:#6c757d; text-align:right; padding:2px 8px;",
          " white-space:nowrap; background:#f8f9fa; border-right:2px solid #dee2e6;"
        )
      ),
      lapply(dates, function(d) {
        slot_id  <- paste0(format(d, "%Y-%m-%d"), "_", sprintf("%02d", as.integer(h)))
        is_valid <- slot_id %in% valid_set

        if (!is_valid) {
          return(shiny::tags$td(style = paste0(
            "background:#ececec; width:60px; height:28px;",
            " border:1px solid #dee2e6; cursor:not-allowed;"
          )))
        }

        cnt <- count_lookup[slot_id]
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

        tooltip <- name_lookup[slot_id]
        if (is.null(tooltip) || is.na(tooltip)) tooltip <- ""

        label <- if (cnt > 0L) {
          shiny::tags$span(
            cnt,
            style = "font-size:0.75em; font-weight:700; color:rgba(255,255,255,0.9); pointer-events:none;"
          )
        } else NULL

        shiny::tags$td(
          class       = "slot-cell",
          `data-slot` = slot_id,
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
