#!/usr/bin/env Rscript

runtime_files <- c(
  "app.R",
  file.path(
    "R",
    c(
      "config.R",
      "database.R",
      "catalog.R",
      "recommendation.R",
      "recommendation_state.R",
      "ui_components.R",
      "app_ui.R",
      "app_server.R"
    )
  ),
  file.path("www", "styles.css"),
  file.path(
    "www",
    "brand",
    c(
      "choco-trail-lockup-horizontal-ink-outlined.svg",
      "favicon.svg"
    )
  )
)

missing_files <- runtime_files[!file.exists(runtime_files)]

if (length(missing_files) > 0L) {
  stop(
    "Cannot write manifest; missing runtime files: ",
    paste(missing_files, collapse = ", "),
    call. = FALSE
  )
}

rsconnect::writeManifest(
  appDir = ".",
  appFiles = runtime_files,
  appPrimaryDoc = "app.R",
  appMode = "shiny",
  dependencyResolution = "library"
)
