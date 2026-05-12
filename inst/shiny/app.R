# meetR — respondent Shiny app
# This file is self-contained: it has no dependency on the meetR package.
# It is launched by meetr_launch() which writes config.rds alongside it.

library(shiny)
library(googlesheets4)
library(dplyr)
library(ggplot2)
library(tidyr)

source("helpers.R")

# ---- Load config written by meetr_launch() -------------------------------

config <- tryCatch(
  readRDS("config.rds"),
  error = function(e) NULL
)

if (is.null(config)) {
  config <- list(
    sheet_id   = Sys.getenv("MEETR_SHEET_ID"),
    event_id   = Sys.getenv("MEETR_EVENT_ID"),
    event_name = Sys.getenv("MEETR_EVENT_NAME", unset = "Untitled Event"),
    app_title  = Sys.getenv("MEETR_APP_TITLE",  unset = "meetR"),
    timezone   = Sys.getenv("MEETR_TIMEZONE",   unset = "UTC"),
    slots      = character(0)
  )
}

SHEET_ID      <- config$sheet_id
EVENT_ID      <- config$event_id
EVENT_NAME    <- config$event_name
APP_TITLE     <- config$app_title
EV_TZ         <- if (!is.null(config$timezone) && nchar(config$timezone) > 0)
                   config$timezone else "UTC"
EV_SLOTS      <- config$slots
EV_EXPECTED_N <- config$expected_n

# ---- Auth ----------------------------------------------------------------

if (file.exists("credentials.json")) {
  gs4_auth(path = "credentials.json")
} else if (dir.exists(".secrets")) {
  gs4_auth(cache = ".secrets", email = TRUE)
}

# ---- Constants -----------------------------------------------------------

EV_DATES <- slots_to_dates(EV_SLOTS)

COMMON_TIMEZONES <- unique(c(
  EV_TZ,
  "UTC",
  "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles",
  "America/Anchorage", "Pacific/Honolulu",
  "America/Toronto", "America/Vancouver", "America/Sao_Paulo",
  "Europe/London", "Europe/Dublin", "Europe/Paris", "Europe/Berlin",
  "Europe/Rome", "Europe/Stockholm", "Europe/Moscow",
  "Africa/Cairo", "Africa/Johannesburg",
  "Asia/Dubai", "Asia/Kolkata", "Asia/Bangkok", "Asia/Singapore",
  "Asia/Shanghai", "Asia/Tokyo", "Asia/Seoul",
  "Australia/Perth", "Australia/Sydney", "Pacific/Auckland"
))

# ---- JS / CSS ------------------------------------------------------------

GRID_JS <- HTML('
$(function() {
  var dragging = false;
  var dragMode = "select";

  function selected() {
    return $(".slot-cell.user-selected").map(function() {
      return $(this).data("slot");
    }).get();
  }

  function syncShiny() {
    Shiny.setInputValue("selected_slots", selected(), {priority: "event"});
  }

  function applyCell(el) {
    if (dragMode === "select") $(el).addClass("user-selected");
    else                        $(el).removeClass("user-selected");
  }

  $(document).on("mousedown", ".slot-cell", function(e) {
    e.preventDefault();
    dragging = true;
    dragMode = $(this).hasClass("user-selected") ? "deselect" : "select";
    applyCell(this);
  });

  $(document).on("mouseover", ".slot-cell", function() {
    if (dragging) applyCell(this);
  });

  $(document).on("mouseup", function() {
    if (dragging) { dragging = false; syncShiny(); }
  });

  Shiny.addCustomMessageHandler("preSelectSlots", function(slots) {
    $(".slot-cell").removeClass("user-selected");
    if (slots && slots.length > 0) {
      slots.forEach(function(s) {
        $(".slot-cell[data-slot=\'" + s + "\']").addClass("user-selected");
      });
    }
    syncShiny();
  });
});
')

GRID_CSS <- HTML('
:root {
  --solar-base03:#002b36;
  --solar-base02:#073642;
  --solar-base1:#93a1a1;
  --solar-base0:#839496;
  --solar-base2:#eee8d5;
  --solar-base3:#fdf6e3;
  --solar-blue:#268bd2;
  --solar-amber:#b58900;
  --solar-amber-soft:#f5e8bf;
}
.slot-cell:hover { opacity:0.85; outline:2px solid var(--solar-blue); outline-offset:-2px; }
.slot-cell.user-selected {
  outline: 3px solid var(--solar-blue) !important;
  outline-offset: -3px;
  background-color: rgba(38,139,210,0.38) !important;
}
.participant-badge {
  display:inline-block; background:var(--solar-base2); border-radius:20px;
  padding:3px 10px; margin:3px; font-size:0.82em;
}
.card {
  background:#fffdf5; border:1px solid var(--solar-base2); border-radius:10px; padding:24px;
  margin-bottom:18px; box-shadow:0 2px 8px rgba(101,86,40,0.08);
}
body { font-family:"Helvetica Neue", Arial, sans-serif; background:var(--solar-base3); color:var(--solar-base02); }
.container-fluid { max-width:1100px; margin:0 auto; padding:24px; }
.app-brand { font-size:2.2rem; font-weight:700; color:var(--solar-blue); letter-spacing:0.5px; }
.app-sub   { color:var(--solar-base0); margin-bottom:24px; }
.btn-primary {
  background-color:var(--solar-blue); border-color:var(--solar-blue);
}
.btn-primary:hover, .btn-primary:focus {
  background-color:#1d73ad; border-color:#1d73ad;
}
.btn-success {
  background-color:var(--solar-amber); border-color:var(--solar-amber);
}
.btn-success:hover, .btn-success:focus {
  background-color:#9d7600; border-color:#9d7600;
}
.btn-outline-secondary {
  color:var(--solar-base0); border-color:var(--solar-base1);
}
.btn-outline-secondary:hover, .btn-outline-secondary:focus {
  background-color:var(--solar-base2); color:var(--solar-base02); border-color:var(--solar-base0);
}
/* Step indicator */
.step-indicator {
  display:flex; align-items:flex-start; margin-bottom:28px;
}
.step-dot {
  display:flex; flex-direction:column; align-items:center; flex-shrink:0;
}
.step-circle {
  width:34px; height:34px; border-radius:50%;
  display:flex; align-items:center; justify-content:center;
  font-weight:700; font-size:0.9em;
  background:var(--solar-base2); color:var(--solar-base0); border:2px solid #d8d0b6;
  transition: background 0.2s, border-color 0.2s;
}
.step-dot.active .step-circle { background:var(--solar-blue); color:white; border-color:var(--solar-blue); }
.step-dot.done   .step-circle { background:var(--solar-amber); color:white; border-color:var(--solar-amber); }
.step-label {
  font-size:0.72em; color:var(--solar-base1); margin-top:5px;
  text-align:center; white-space:nowrap;
}
.step-dot.active .step-label { color:var(--solar-blue); font-weight:600; }
.step-dot.done   .step-label { color:var(--solar-amber); }
.step-line {
  flex:1; height:2px; background:var(--solar-base2); margin:0 10px; margin-top:17px;
  transition: background 0.2s;
}
.step-line.done { background:var(--solar-amber); }
/* Step nav buttons row */
.step-nav { display:flex; justify-content:flex-end; gap:8px; margin-bottom:14px; }
/* Slot summary in step 3 */
.summary-day { margin-bottom:6px; font-size:0.93em; }
.summary-empty { color:var(--solar-base0); font-style:italic; }
/* Footer */
.app-footer {
  text-align:center; padding:18px 0 28px 0; color:var(--solar-base1); font-size:0.82em;
}
.app-footer a {
  color:var(--solar-base0); text-decoration:none; display:inline-flex;
  align-items:center; gap:6px; transition:color 0.15s;
}
.app-footer a:hover { color:var(--solar-blue); }
.app-footer svg { vertical-align:middle; }
')

# ---- UI ------------------------------------------------------------------

ui <- fluidPage(
  tags$head(
    tags$title(APP_TITLE),
    tags$style(GRID_CSS),
    tags$script(GRID_JS)
  ),
  div(class = "container-fluid",
    div(class = "app-brand", APP_TITLE),
    div(class = "app-sub", EVENT_NAME),

    if (length(EV_SLOTS) == 0) {
      div(class = "card", style = "border-left:4px solid #dc3545;",
        h3("Configuration error"),
        p("No availability slots found. Please re-run meetr_launch().")
      )
    } else {
      div(
        # Event header
        div(class = "card", style = "padding:14px 24px;",
          h2(EVENT_NAME, style = "margin:0;"),
          p(
            format(min(EV_DATES), "%b %d"), "–",
            format(max(EV_DATES), "%b %d, %Y"),
            HTML(paste0(
              "&nbsp;&middot;&nbsp;",
              "<span style='background:#eee8d5; border-radius:4px;",
              " padding:1px 7px; font-size:0.82em;'>",
              "Organizer timezone: ", EV_TZ, "</span>"
            )),
            style = "color:#839496; margin:4px 0 0 0;"
          )
        ),
        # Wizard card
        div(class = "card",
          uiOutput("step_indicator"),
          uiOutput("step_ui")
        ),
        # Participants (always visible)
        div(class = "card", style = "padding:16px 24px;",
          strong("Participants"),
          uiOutput("participant_badges")
        ),
        uiOutput("heatmap_section"),
        div(class = "app-footer",
          tags$a(
            href   = "https://github.com/kartiktrivedi/meetR",
            target = "_blank",
            HTML('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 98 96" fill="currentColor"><path fill-rule="evenodd" clip-rule="evenodd" d="M48.854 0C21.839 0 0 22 0 49.217c0 21.756 13.993 40.172 33.405 46.69 2.427.49 3.316-1.059 3.316-2.362 0-1.141-.08-5.052-.08-9.127-13.59 2.934-16.42-5.867-16.42-5.867-2.184-5.704-5.42-7.17-5.42-7.17-4.448-3.015.324-3.015.324-3.015 4.934.326 7.523 5.052 7.523 5.052 4.367 7.496 11.404 5.378 14.235 4.074.404-3.178 1.699-5.378 3.074-6.6-10.839-1.141-22.243-5.378-22.243-24.283 0-5.378 1.94-9.778 5.014-13.2-.485-1.222-2.184-6.275.486-13.038 0 0 4.125-1.304 13.426 5.052a46.97 46.97 0 0 1 12.214-1.63c4.125 0 8.33.571 12.213 1.63 9.302-6.356 13.427-5.052 13.427-5.052 2.67 6.763.97 11.816.485 13.038 3.155 3.422 5.015 7.822 5.015 13.2 0 18.905-11.404 23.06-22.324 24.283 1.78 1.548 3.316 4.481 3.316 9.126 0 6.6-.08 11.897-.08 13.526 0 1.304.89 2.853 3.316 2.364 19.412-6.52 33.405-24.935 33.405-46.691C97.707 22 75.788 0 48.854 0z"/></svg>'),
            "kartiktrivedi/meetR"
          )
        )
      )
    }
  )
)

# ---- Server --------------------------------------------------------------

server <- function(input, output, session) {

  step            <- reactiveVal(1L)
  saved_slots     <- reactiveVal(character(0))
  refresh_trigger <- reactiveVal(0L)

  responses <- reactive({
    refresh_trigger()
    get_responses(SHEET_ID, EVENT_ID)
  })

  slot_counts <- reactive({
    compute_slot_counts(responses())
  })

  slot_map <- reactive({
    tz <- input$resp_tz %||% EV_TZ
    slots_in_tz(EV_SLOTS, EV_TZ, tz)
  })

  # ---- Step indicator ---------------------------------------------------

  output$step_indicator <- renderUI({
    s <- step()
    defs <- list(
      list(n = 1L, label = "Your Info"),
      list(n = 2L, label = "Select Times"),
      list(n = 3L, label = "Confirm & Save")
    )
    items <- lapply(seq_along(defs), function(i) {
      d         <- defs[[i]]
      is_active <- d$n == s
      is_done   <- d$n < s
      cls <- paste0("step-dot",
                    if (is_active) " active" else if (is_done) " done" else "")
      line <- if (i < length(defs))
        div(class = paste0("step-line", if (is_done) " done" else ""))
      else NULL
      tagList(
        div(class = cls,
          div(class = "step-circle",
            if (is_done) HTML("&#10003;") else as.character(d$n)),
          div(class = "step-label", d$label)
        ),
        line
      )
    })
    div(class = "step-indicator", items)
  })

  # ---- Step content -----------------------------------------------------

  output$step_ui <- renderUI({
    switch(step(),
      `1` = div(style = "max-width:440px;",
        textInput("user_name", "Your Name",
          value       = isolate(input$user_name %||% ""),
          placeholder = "Enter your name…"),
        div(style = "margin-top:12px;",
          selectInput("resp_tz", "View times in:",
            choices  = COMMON_TIMEZONES,
            selected = isolate(input$resp_tz %||% EV_TZ),
            width    = "100%")
        ),
        div(style = "margin-top:20px;",
          actionButton("btn_next_1", "Continue →",
            class = "btn btn-primary",
            style = "padding:8px 28px;")
        )
      ),

      `2` = div(
        div(class = "step-nav",
          actionButton("btn_back_2", "← Back",
            class = "btn btn-outline-secondary btn-sm"),
          actionButton("btn_next_2", "Next →",
            class = "btn btn-primary btn-sm")
        ),
        uiOutput("grid_header"),
        div(style = "overflow-x:auto;", uiOutput("grid_ui"))
      ),

      `3` = div(
        uiOutput("slot_summary"),
        div(style = "margin-top:24px; display:flex; gap:10px;",
          actionButton("btn_back_3", "← Back",
            class = "btn btn-outline-secondary"),
          actionButton("btn_submit", "Save My Availability",
            class = "btn btn-success")
        )
      )
    )
  })

  # ---- Grid outputs (used in step 2) ------------------------------------

  output$grid_header <- renderUI({
    tz <- input$resp_tz %||% EV_TZ
    p(HTML(paste0(
      "<b>Click or drag</b> to mark when you're free.&nbsp;",
      "<span style='color:#268bd2;font-weight:bold;'>Blue</span>",
      " = your selection &nbsp;|&nbsp; ",
      "<span style='color:#b58900;font-weight:bold;'>Amber</span>",
      " = group overlap &nbsp;|&nbsp; ",
      "<span style='color:#93a1a1;'>Warm grey</span> = outside this event",
      "&nbsp;&nbsp;<b>All times: ", tz, "</b>"
    )),
    style = "font-size:0.88em; color:#839496; margin-bottom:10px;")
  })

  output$grid_ui <- renderUI({
    n_users <- n_distinct(responses()$user_name)
    build_grid(slot_map(), slot_counts(), n_users)
  })

  # ---- Slot summary (step 3) --------------------------------------------

  output$slot_summary <- renderUI({
    slots <- saved_slots()
    uname <- trimws(input$user_name %||% "")
    tz    <- input$resp_tz %||% EV_TZ

    name_line <- div(style = "margin-bottom:14px;",
      "Submitting for: ",
      tags$strong(uname),
      HTML(paste0(
        "&nbsp;<span style='background:#eee8d5; border-radius:4px;",
        " padding:1px 7px; font-size:0.82em; color:#073642;'>", tz, "</span>"
      ))
    )

    if (length(slots) == 0) {
      return(tagList(
        name_line,
        p(class = "summary-empty",
          "No slots selected — you will be marked as unavailable for all times.")
      ))
    }

    dates <- sort(unique(substr(slots, 1, 10)))
    tagList(
      name_line,
      p(paste0(length(slots), " slot(s) across ", length(dates), " day(s):"),
        style = "color:#839496; font-size:0.88em; margin-bottom:10px;"),
      lapply(dates, function(d) {
        day_slots <- sort(slots[substr(slots, 1, 10) == d])
        times_str <- paste(sapply(day_slots, function(sl) {
          format_slot_time(as.integer(substr(sl, 12, 13)),
                           as.integer(substr(sl, 15, 16)))
        }), collapse = ", ")
        div(class = "summary-day",
          tags$strong(format(as.Date(d), "%A, %b %d")),
          " — ", times_str
        )
      })
    )
  })

  # ---- Participants (always visible) ------------------------------------

  output$participant_badges <- renderUI({
    resp <- responses()
    n    <- n_distinct(resp$user_name)

    progress_ui <- if (!is.null(EV_EXPECTED_N)) {
      pct   <- min(100L, round(n / EV_EXPECTED_N * 100L))
      color <- if (n >= EV_EXPECTED_N) "#b58900" else "#268bd2"
      tagList(
        div(style = "margin:6px 0 10px 0;",
          div(
            span(as.character(n),
              style = paste0("font-weight:700; color:", color, ";")),
            span(paste0(" / ", EV_EXPECTED_N, " responded"),
              style = "color:#839496;"),
            style = "font-size:0.88em; margin-bottom:4px;"
          ),
          div(style = "background:#eee8d5; border-radius:4px; height:6px;",
            div(style = paste0(
              "background:", color, "; border-radius:4px;",
              " height:6px; width:", pct, "%;",
              " transition:width 0.4s ease;"
            ))
          )
        )
      )
    } else NULL

    if (n == 0) {
      return(tagList(
        progress_ui,
        p("No responses yet.",
          style = "color:#839496; font-size:0.88em; margin-top:4px;")
      ))
    }
    tagList(
      progress_ui,
      lapply(unique(resp$user_name), function(u) {
        span(class = "participant-badge", "\U0001f464 ", u)
      })
    )
  })

  # ---- Step navigation --------------------------------------------------

  observeEvent(input$btn_next_1, {
    uname <- trimws(input$user_name %||% "")
    if (nchar(uname) == 0) {
      showNotification("Please enter your name before continuing.",
        type = "warning", duration = 3)
      return()
    }
    step(2L)
  })

  # Pre-fill grid after step 2 renders (two flush cycles: step_ui then grid_ui)
  observeEvent(step(), {
    req(step() == 2L)
    uname <- trimws(isolate(input$user_name %||% ""))
    # Prefer slots saved in this session; fall back to prior GSheets submission
    prev <- isolate(saved_slots())
    if (length(prev) == 0) {
      resp  <- isolate(responses())
      match <- resp[resp$user_name == uname, ]
      if (nrow(match) > 0 && !is.na(match$slots[1]) && match$slots[1] != "") {
        prev <- unlist(strsplit(match$slots[1], ","))
      }
    }
    if (length(prev) > 0) {
      slots_to_send <- prev
      session$onFlushed(function() {
        session$onFlushed(function() {
          session$sendCustomMessage("preSelectSlots", as.list(slots_to_send))
        }, once = TRUE)
      }, once = TRUE)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$btn_back_2, { step(1L) })

  observeEvent(input$btn_next_2, {
    saved_slots(input$selected_slots %||% character(0))
    step(3L)
  })

  observeEvent(input$btn_back_3, { step(2L) })

  observeEvent(input$btn_submit, {
    uname <- trimws(input$user_name %||% "")
    req(nchar(uname) > 0)

    slots <- saved_slots()

    outcome <- tryCatch({
      save_response(SHEET_ID, EVENT_ID, uname, slots)
      "ok"
    }, error = function(e) paste0("error: ", e$message))

    if (startsWith(outcome, "error")) {
      showNotification(paste("Could not save:", outcome),
        type = "error", duration = 8)
      return()
    }

    refresh_trigger(refresh_trigger() + 1L)
    showNotification(
      paste0("Saved! ", length(slots), " slot(s) recorded for ", uname, "."),
      type = "message", duration = 4
    )
    saved_slots(character(0))
    step(1L)
  })

  # ---- Heatmap ----------------------------------------------------------

  output$heatmap_section <- renderUI({
    if (nrow(responses()) == 0) return(NULL)
    div(class = "card",
      h4("Group Availability Heatmap"),
      p(paste0("Each cell shows how many people are free at that time. ",
               "Times shown in organizer timezone (", EV_TZ, ")."),
        style = "color:#839496; font-size:0.88em;"),
      plotOutput("heatmap_plot", height = "300px")
    )
  })

  output$heatmap_plot <- renderPlot({
    sc      <- slot_counts()
    n_users <- n_distinct(responses()$user_name)
    if (nrow(sc) == 0 || n_users == 0) return(NULL)

    skeleton <- data.frame(slot = EV_SLOTS, stringsAsFactors = FALSE) |>
      mutate(
        slot_date = as.Date(substr(slot, 1, 10)),
        slot_mins = as.integer(substr(slot, 12, 13)) * 60L +
                    as.integer(substr(slot, 15, 16))
      )

    plot_data <- skeleton |>
      left_join(sc, by = "slot") |>
      mutate(count = tidyr::replace_na(count, 0L))

    all_mins <- sort(unique(plot_data$slot_mins))

    ggplot(plot_data,
      aes(
        x    = factor(slot_date),
        y    = factor(slot_mins, levels = rev(all_mins)),
        fill = count
      )
    ) +
      geom_tile(color = "white", linewidth = 0.4) +
      geom_text(
        data = filter(plot_data, count > 0),
        aes(label = count), size = 3.5, color = "#073642", fontface = "bold"
      ) +
      scale_fill_gradient(
        low = "#fdf6e3", high = "#b58900",
        limits = c(0, n_users), name = "# Available"
      ) +
      scale_x_discrete(labels = function(x) format(as.Date(x), "%a\n%m/%d")) +
      scale_y_discrete(labels = function(y) {
        mins <- as.integer(y)
        format_slot_time(mins %/% 60L, mins %% 60L)
      }) +
      labs(x = NULL, y = NULL) +
      theme_minimal(base_size = 13) +
      theme(
        panel.grid      = element_blank(),
        axis.text.x     = element_text(angle = 0, hjust = 0.5),
        legend.position = "right"
      )
  })
}

`%||%` <- function(a, b) if (is.null(a)) b else a

shinyApp(ui, server)
