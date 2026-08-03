#!/usr/bin/env Rscript

# This stage is preview-only. MotherDuck publication is added only after
# validation and compatibility previews are reviewed.

source(file.path("R", "config.R"))
source(file.path("R", "database.R"))
source(file.path("scripts", "lib", "catalog_io.R"))
source(file.path("scripts", "lib", "catalog_validation.R"))
source(file.path("scripts", "lib", "compatibility.R"))

preview_catalog_publication <- function() {
  message("Reading the Google Sheet in read-only mode...")
  raw_catalog <- read_catalog_sheet()
  validation <- validate_catalog(raw_catalog)

  if (nrow(validation$issues) > 0L) {
    print(validation$issues, n = Inf)
  }

  if (catalog_has_errors(validation)) {
    stop(
      "Catalog validation failed. Correct the reported Sheet values and preview again.",
      call. = FALSE
    )
  }

  catalog_counts <- validation$data |>
    dplyr::count(category, active, name = "items") |>
    dplyr::arrange(category, dplyr::desc(active))

  message("Catalog validation passed.")
  print(catalog_counts, n = Inf)
  message("Total catalog rows: ", nrow(validation$data))

  outfits <- generate_outfits(validation$data)
  compatibility_counts <- summarize_compatibility(outfits)

  message("Compatibility preview:")
  print(compatibility_counts, n = Inf)
  message("Total generated outfits: ", nrow(outfits))

  message("Comparing with MotherDuck in read-only mode...")
  connection <- db_connect_motherduck()
  on.exit(db_disconnect(connection), add = TRUE)
  publication_plan <- build_catalog_publish_plan(
    connection,
    validation$data,
    outfits
  )

  if (nrow(publication_plan$issues) > 0L) {
    print(publication_plan$issues, n = Inf)
  }

  if (catalog_has_errors(publication_plan)) {
    stop(
      "Publication preview failed its existing-catalog checks.",
      call. = FALSE
    )
  }

  message("MotherDuck publication plan:")
  print(publication_plan$summary, n = Inf)
  message("Protected application state (read only):")
  print(publication_plan$protected_counts, n = Inf)
  message("Dry run passed. Nothing was written to MotherDuck.")

  invisible(list(
    catalog = validation$data,
    outfits = outfits,
    publication_plan = publication_plan
  ))
}

preview_catalog_publication()
