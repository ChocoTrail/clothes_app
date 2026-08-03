clothes_app_config <- list(
  spreadsheet_id = "1bJhNJWLV1vdM4jDoC6T2lUOMbBhPdkywE5tSejeauN0",
  spreadsheet_tab = "data",
  motherduck_database = "choco_trail",
  database_schema = "clothes_app",
  display_timezone = "America/Los_Angeles",
  settings_id = "singleton",
  weather_modes = c("warm", "cold"),
  recommendation_statuses = c(
    "active",
    "rerolled",
    "worn",
    "season_invalidated"
  )
)

validate_config <- function(config = clothes_app_config) {
  identifier_pattern <- "^[A-Za-z_][A-Za-z0-9_]*$"
  identifiers <- unlist(
    config[c("motherduck_database", "database_schema")],
    use.names = TRUE
  )

  invalid_identifiers <- !grepl(identifier_pattern, identifiers)

  if (any(invalid_identifiers)) {
    stop(
      "Database and schema names must be safe SQL identifiers: ",
      paste(names(identifiers)[invalid_identifiers], collapse = ", "),
      call. = FALSE
    )
  }

  if (!identical(config$weather_modes, c("warm", "cold"))) {
    stop("Weather modes must be warm and cold.", call. = FALSE)
  }

  invisible(config)
}

motherduck_token <- function() {
  token <- Sys.getenv("MOTHERDUCK_TOKEN", unset = "")

  if (!nzchar(token)) {
    stop(
      "MOTHERDUCK_TOKEN is required for a MotherDuck connection. ",
      "Set it in the local environment or deployment secrets.",
      call. = FALSE
    )
  }

  token
}
