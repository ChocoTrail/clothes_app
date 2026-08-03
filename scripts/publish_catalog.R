#!/usr/bin/env Rscript

# This stage is preview-only. MotherDuck publication is added only after
# validation and compatibility previews are reviewed.

source(file.path("R", "config.R"))
source(file.path("scripts", "lib", "catalog_io.R"))
source(file.path("scripts", "lib", "catalog_validation.R"))

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

message("Catalog validation passed. Nothing was written to MotherDuck.")
print(catalog_counts, n = Inf)
message("Total catalog rows: ", nrow(validation$data))
