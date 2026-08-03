#!/usr/bin/env Rscript

runtime_files <- c("app.R")

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
