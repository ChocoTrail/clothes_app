library(shiny)
library(bslib)

ui <- page_fillable(
  theme = bs_theme(version = 5),
  title = "Clothes App",
  card(
    card_header("Clothes App"),
    p("The project environment and deployment path are ready for verification."),
    p("Outfit recommendations will be added in the next implementation stages.")
  )
)

server <- function(input, output, session) {
  invisible(NULL)
}

shinyApp(ui, server)
