db_connect_local <- function(
  dbdir = ":memory:",
  read_only = FALSE,
  shared_home = FALSE
) {
  DBI::dbConnect(
    duckdb::duckdb(shared_home = shared_home),
    dbdir = dbdir,
    read_only = read_only
  )
}

db_disconnect <- function(connection) {
  if (!is.null(connection) && DBI::dbIsValid(connection)) {
    DBI::dbDisconnect(connection)
  }

  invisible(NULL)
}

db_connect_motherduck <- function(config = clothes_app_config) {
  validate_config(config)
  token <- motherduck_token()
  prior_extension_token <- Sys.getenv("motherduck_token", unset = NA_character_)

  on.exit({
    if (is.na(prior_extension_token)) {
      Sys.unsetenv("motherduck_token")
    } else {
      do.call(
        Sys.setenv,
        setNames(list(prior_extension_token), "motherduck_token")
      )
    }
  }, add = TRUE)

  do.call(Sys.setenv, setNames(list(token), "motherduck_token"))
  connection <- db_connect_local(shared_home = TRUE)

  tryCatch(
    {
      DBI::dbExecute(connection, "INSTALL motherduck")
      DBI::dbExecute(connection, "LOAD motherduck")

      database_identifier <- DBI::dbQuoteIdentifier(
        connection,
        config$motherduck_database
      )
      attach_statement <- sprintf(
        "ATTACH 'md:%s' AS %s",
        config$motherduck_database,
        database_identifier
      )

      DBI::dbExecute(connection, attach_statement)
      DBI::dbExecute(connection, paste("USE", database_identifier))
      connection
    },
    error = function(error) {
      db_disconnect(connection)
      stop(
        "Could not connect to MotherDuck: ",
        conditionMessage(error),
        call. = FALSE
      )
    }
  )
}

read_schema_sql <- function(schema_path = file.path("db", "schema.sql")) {
  if (!file.exists(schema_path)) {
    stop("Schema file does not exist: ", schema_path, call. = FALSE)
  }

  paste(readLines(schema_path, warn = FALSE), collapse = "\n")
}

initialize_database_schema <- function(
  connection,
  schema_path = file.path("db", "schema.sql")
) {
  schema_sql <- read_schema_sql(schema_path)
  DBI::dbExecute(connection, schema_sql)
  invisible(connection)
}

database_contract_summary <- function(
  connection,
  config = clothes_app_config
) {
  objects <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT table_name, table_type",
      "FROM information_schema.tables",
      "WHERE table_schema = ?",
      "ORDER BY table_name"
    ),
    params = list(config$database_schema)
  )

  settings <- DBI::dbGetQuery(
    connection,
    sprintf(
      "SELECT settings_id, weather_mode, active_recommendation_id, state_version FROM %s.app_settings",
      DBI::dbQuoteIdentifier(connection, config$database_schema)
    )
  )

  list(objects = objects, settings = settings)
}
