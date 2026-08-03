# Clothes App

A Choco Trail R Shiny app that recommends one work outfit from a personal wardrobe.

The product specification, planned file structure, and staged implementation order live in [`DESIGN.md`](DESIGN.md).

## Development status

Stage 1 is establishing the `rv`-managed R environment and validating the minimal Shiny-to-Connect-Cloud deployment path. Product and database behavior will be added in the later stages defined by the design.

## Local setup

1. Install R 4.6 and [`rv`](https://a2-ai.github.io/rv-docs/intro/installation/).
2. Run `rv sync` from the project root.
3. Start the app with `Rscript -e 'shiny::runApp()'`.

Never commit a real MotherDuck token. When database work begins, copy `.Renviron.example` to `.Renviron` and fill in the local value.
