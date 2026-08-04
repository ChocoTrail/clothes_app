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
      shiny::tags$link(rel = "stylesheet", href = "styles.css")
    ),
    shiny::div(
      class = "app-shell",
      shiny::tags$header(
        class = "app-header",
        shiny::div(
          shiny::p(class = "app-header__signature", "A Choco Trail project"),
          shiny::h1("Clothes App")
        ),
        shiny::uiOutput("weather_mode")
      ),
      shiny::tags$main(
        class = "app-main",
        shiny::uiOutput("notice"),
        shiny::uiOutput("decision_view")
      ),
      shiny::tags$footer(
        class = "app-footer",
        "Made for quieter morning decisions."
      )
    )
  )
}
