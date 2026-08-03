#!/usr/bin/env Rscript

find_publish_project_root <- function(start = getwd()) {
  candidate <- normalizePath(start, mustWork = TRUE)

  repeat {
    if (
      file.exists(file.path(candidate, "DESIGN.md"))
      && file.exists(file.path(candidate, "clothes_app.Rproj"))
    ) {
      return(candidate)
    }

    parent <- dirname(candidate)
    if (identical(parent, candidate)) {
      stop("Could not locate the clothes_app project root.", call. = FALSE)
    }
    candidate <- parent
  }
}

publish_project_root <- find_publish_project_root()

source(file.path(publish_project_root, "R", "config.R"))
source(file.path(publish_project_root, "R", "database.R"))
source(
  file.path(publish_project_root, "scripts", "lib", "catalog_io.R")
)
source(
  file.path(publish_project_root, "scripts", "lib", "catalog_validation.R")
)
source(
  file.path(publish_project_root, "scripts", "lib", "compatibility.R")
)

catalog_target_connection <- function(target) {
  local_config <- clothes_app_config
  local_config$local_database_path <- file.path(
    publish_project_root,
    clothes_app_config$local_database_path
  )

  switch(
    target,
    local = db_connect_local_app(local_config),
    motherduck = db_connect_motherduck()
  )
}

catalog_target_label <- function(target) {
  switch(target, local = "Local", motherduck = "MotherDuck")
}

publish_catalog <- function(
  target = c("local", "motherduck"),
  write = FALSE,
  raw_catalog = NULL,
  connection = NULL
) {
  target <- match.arg(target)

  if (length(write) != 1L || is.na(write) || !is.logical(write)) {
    stop("write must be one TRUE or FALSE value.", call. = FALSE)
  }

  if (write && target == "motherduck") {
    stop(
      "MotherDuck writes are not enabled yet. Preview it or target local.",
      call. = FALSE
    )
  }

  if (is.null(raw_catalog)) {
    message("Reading the Google Sheet in read-only mode...")
    raw_catalog <- read_catalog_sheet()
  }

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

  owns_connection <- is.null(connection)
  if (owns_connection) {
    message("Connecting to the ", target, " database...")
    connection <- catalog_target_connection(target)
    on.exit(db_disconnect(connection), add = TRUE)
  }

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

  message(catalog_target_label(target), " publication plan:")
  print(publication_plan$summary, n = Inf)
  message("Protected application state (read only):")
  print(publication_plan$protected_counts, n = Inf)

  receipt <- NULL
  if (write) {
    receipt <- publish_catalog_transaction(
      connection,
      validation$data,
      outfits
    )
    message(
      "Local catalog publication committed with ID ",
      receipt$publication_id,
      "."
    )
  } else {
    message("Dry run passed. Nothing was written to ", target, ".")
  }

  invisible(list(
    catalog = validation$data,
    outfits = outfits,
    publication_plan = publication_plan,
    receipt = receipt
  ))
}

parse_catalog_publish_arguments <- function(arguments) {
  allowed_arguments <- c("--local", "--write")
  unknown_arguments <- setdiff(arguments, allowed_arguments)

  if (length(unknown_arguments) > 0L) {
    stop(
      "Usage: Rscript scripts/publish_catalog.R [--local] [--write]",
      call. = FALSE
    )
  }

  list(
    target = if ("--local" %in% arguments) "local" else "motherduck",
    write = "--write" %in% arguments
  )
}

if (sys.nframe() == 0L) {
  options <- parse_catalog_publish_arguments(commandArgs(trailingOnly = TRUE))
  publish_catalog(target = options$target, write = options$write)
}
