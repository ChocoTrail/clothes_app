clothes_app_theme <- function() {
  bslib::bs_theme(
    version = 5,
    bg = "#F4F3EF",
    fg = "#22292B",
    primary = "#2F6F73"
  )
}

app_ui <- function() {
  bslib::page_fillable(
    title = "Clothes App",
    theme = clothes_app_theme(),
    fillable_mobile = TRUE,
    shiny::tags$head(
      shiny::tags$link(
        rel = "icon",
        type = "image/svg+xml",
        href = "brand/favicon.svg"
      ),
      shiny::tags$link(rel = "stylesheet", href = "styles.css")
    ),
    shiny::div(
      class = "app-shell",
      shiny::tags$header(
        class = "app-header",
        shiny::h1("Clothes App"),
        shiny::uiOutput("weather_control")
      ),
      shiny::tags$main(
        class = "app-main",
        shiny::uiOutput("notice"),
        shiny::div(
          class = "app-navigation",
          bslib::navset_underline(
            id = "app_view",
            selected = "today",
            bslib::nav_panel(
              "Today",
              value = "today",
              shiny::uiOutput("decision_view")
            ),
            bslib::nav_panel(
              "History",
              value = "history",
              shiny::uiOutput("history_view")
            )
          )
        )
      ),
      shiny::tags$footer(
        class = "app-footer",
        shiny::tags$img(
          class = "app-footer__lockup",
          src = "brand/choco-trail-lockup-horizontal-ink-outlined.svg",
          alt = "Choco Trail"
        )
      )
    )
  )
}
