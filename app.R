options(
  shiny.devmode.verbose = FALSE,
  shiny.autoreload.legacy_warning = FALSE,
  bslib.color_contrast_warnings = FALSE
)

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
})

source(file.path("R", "config.R"))
source(file.path("R", "database.R"))
source(file.path("R", "catalog.R"))
source(file.path("R", "recommendation.R"))
source(file.path("R", "recommendation_state.R"))
source(file.path("R", "ui_components.R"))
source(file.path("R", "app_ui.R"))
source(file.path("R", "app_server.R"))

shinyApp(ui = app_ui(), server = app_server)
