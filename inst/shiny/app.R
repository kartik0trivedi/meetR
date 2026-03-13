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
  # Fallback: allows the app to start even without config (shows error UI)
  config <- list(
    sheet_id   = Sys.getenv("MEETR_SHEET_ID"),
    event_id   = Sys.getenv("MEETR_EVENT_ID"),
    event_name = Sys.getenv("MEETR_EVENT_NAME", unset = "Untitled Event"),
    app_title  = Sys.getenv("MEETR_APP_TITLE",  unset = "meetR"),
    slots      = character(0)
  )
}

SHEET_ID   <- config$sheet_id
EVENT_ID   <- config$event_id
EVENT_NAME <- config$event_name
APP_TITLE  <- config$app_title
EV_SLOTS   <- config$slots

# ---- Auth ----------------------------------------------------------------

if (file.exists("credentials.json")) {
  gs4_auth(path = "credentials.json")
} else if (dir.exists(".secrets")) {
  gs4_auth(cache = ".secrets", email = TRUE)
}
# If neither exists the app will rely on a pre-authenticated session
# (e.g. when run locally via meetr_launch()).

# ---- Constants from config -----------------------------------------------

EV_DATES <- slots_to_dates(EV_SLOTS)
EV_HOURS <- slots_to_hours(EV_SLOTS)

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
.slot-cell:hover { opacity:0.8; outline:2px solid #0d6efd; outline-offset:-2px; }
.slot-cell.user-selected {
  outline: 3px solid #0d6efd !important;
  outline-offset: -3px;
  background-color: rgba(13,110,253,0.45) !important;
}
.participant-badge {
  display:inline-block; background:#e9ecef; border-radius:20px;
  padding:3px 10px; margin:3px; font-size:0.82em;
}
.card {
  background:white; border-radius:10px; padding:24px;
  margin-bottom:18px; box-shadow:0 2px 8px rgba(0,0,0,0.07);
}
body { font-family:"Helvetica Neue", Arial, sans-serif; background:#f4f6f9; }
.container-fluid { max-width:1100px; margin:0 auto; padding:24px; }
.app-brand { font-size:2.2rem; font-weight:900; color:#0d6efd; letter-spacing:-2px; }
.app-sub   { color:#6c757d; margin-bottom:24px; }
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
            format(min(EV_DATES), "%b %d"), "\u2013",
            format(max(EV_DATES), "%b %d, %Y"),
            style = "color:#6c757d; margin:4px 0 0 0;"
          )
        ),
        # Main card
        div(class = "card",
          fluidRow(
            column(3,
              textInput("user_name", "Your Name",
                placeholder = "Enter your name\u2026"),
              actionButton("btn_submit", "Save My Availability",
                class = "btn-success",
                style = "width:100%; margin-top:8px;"),
              hr(),
              strong("Participants"),
              uiOutput("participant_badges")
            ),
            column(9,
              p(HTML(paste0(
                "<b>Click or drag</b> to mark when you're free.&nbsp;",
                "<span style='color:#0d6efd;font-weight:bold;'>Blue</span>",
                " = your selection &nbsp;|&nbsp; ",
                "<span style='color:#2e7d32;font-weight:bold;'>Green</span>",
                " = group overlap &nbsp;|&nbsp; ",
                "<span style='color:#aaa;'>Grey</span> = outside this event"
              )),
              style = "font-size:0.88em; color:#6c757d; margin-bottom:8px;"),
              div(style = "overflow-x:auto;", uiOutput("grid_ui"))
            )
          )
        ),
        uiOutput("heatmap_section")
      )
    }
  )
)

# ---- Server --------------------------------------------------------------

server <- function(input, output, session) {

  refresh_trigger <- reactiveVal(0L)

  responses <- reactive({
    refresh_trigger()
    get_responses(SHEET_ID, EVENT_ID)
  })

  slot_counts <- reactive({
    compute_slot_counts(responses())
  })

  output$grid_ui <- renderUI({
    n_users <- n_distinct(responses()$user_name)
    build_grid(EV_DATES, EV_HOURS, EV_SLOTS, slot_counts(), n_users)
  })

  output$participant_badges <- renderUI({
    resp <- responses()
    if (nrow(resp) == 0) {
      return(p("No responses yet.",
        style = "color:#6c757d; font-size:0.88em; margin-top:8px;"))
    }
    tagList(lapply(unique(resp$user_name), function(u) {
      span(class = "participant-badge", "\U0001f464 ", u)
    }))
  })

  # Pre-fill user's previous selections when they type their name
  observeEvent(input$user_name, {
    req(nchar(trimws(input$user_name %||% "")) > 0)
    resp  <- responses()
    match <- resp[resp$user_name == trimws(input$user_name), ]
    prev  <- if (nrow(match) > 0 && !is.na(match$slots[1]) && match$slots[1] != "") {
      unlist(strsplit(match$slots[1], ","))
    } else character(0)
    session$sendCustomMessage("preSelectSlots", as.list(prev))
  }, ignoreInit = TRUE)

  observeEvent(input$btn_submit, {
    uname <- trimws(input$user_name %||% "")
    req(nchar(uname) > 0)

    slots <- input$selected_slots %||% character(0)

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
  })

  output$heatmap_section <- renderUI({
    if (nrow(responses()) == 0) return(NULL)
    div(class = "card",
      h4("Group Availability Heatmap"),
      p("Each cell shows how many people are free at that time.",
        style = "color:#6c757d; font-size:0.88em;"),
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
        slot_hour = as.integer(substr(slot, 12, 13))
      )

    plot_data <- skeleton |>
      left_join(sc, by = "slot") |>
      mutate(count = tidyr::replace_na(count, 0L))

    all_hours <- sort(unique(plot_data$slot_hour))

    ggplot(plot_data,
      aes(
        x    = factor(slot_date),
        y    = factor(slot_hour, levels = rev(all_hours)),
        fill = count
      )
    ) +
      geom_tile(color = "white", linewidth = 0.4) +
      geom_text(
        data = filter(plot_data, count > 0),
        aes(label = count), size = 3.5, color = "white", fontface = "bold"
      ) +
      scale_fill_gradient(
        low = "#e8f5e9", high = "#2e7d32",
        limits = c(0, n_users), name = "# Available"
      ) +
      scale_x_discrete(labels = function(x) format(as.Date(x), "%a\n%m/%d")) +
      scale_y_discrete(labels = function(y) format_hour(as.integer(y))) +
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
