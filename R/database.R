db_connect_local <- function(
  dbdir = ":memory:",
  read_only = FALSE
) {
  DBI::dbConnect(
    duckdb::duckdb(),
    dbdir = dbdir,
    read_only = read_only
  )
}

db_connect_local_app <- function(config = clothes_app_config) {
  validate_config(config)
  database_path <- config$local_database_path
  database_directory <- dirname(database_path)

  if (!dir.exists(database_directory)) {
    directory_created <- dir.create(
      database_directory,
      recursive = TRUE,
      showWarnings = FALSE
    )

    if (!directory_created && !dir.exists(database_directory)) {
      stop(
        "Could not create the local database directory: ",
        database_directory,
        call. = FALSE
      )
    }
  }

  db_connect_local(database_path)
}

db_table_name <- function(
  connection,
  table,
  config = clothes_app_config
) {
  as.character(
    DBI::dbQuoteIdentifier(
      connection,
      DBI::Id(schema = config$database_schema, table = table)
    )
  )
}

db_new_uuid <- function(connection) {
  DBI::dbGetQuery(
    connection,
    "SELECT CAST(uuid() AS VARCHAR) AS id"
  )$id[[1]]
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
  connection <- db_connect_local()

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

db_connect_app <- function(
  config = clothes_app_config,
  target = app_database_target(config)
) {
  target <- validate_database_target(target, config)

  switch(
    target,
    local = db_connect_local_app(config),
    motherduck = db_connect_motherduck(config)
  )
}

read_schema_sql <- function(schema_path = file.path("db", "schema.sql")) {
  if (!file.exists(schema_path)) {
    stop("Schema file does not exist: ", schema_path, call. = FALSE)
  }

  paste(readLines(schema_path, warn = FALSE), collapse = "\n")
}

database_column_names <- function(
  connection,
  table,
  config = clothes_app_config
) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT column_name",
      "FROM information_schema.columns",
      "WHERE table_schema = ? AND table_name = ?",
      "ORDER BY ordinal_position"
    ),
    params = list(config$database_schema, table)
  )$column_name
}

migrate_recommendation_worn_date <- function(
  connection,
  schema_sql,
  config = clothes_app_config
) {
  columns <- database_column_names(
    connection,
    "recommendations",
    config
  )
  has_resolved_at <- "resolved_at" %in% columns
  has_worn_on <- "worn_on" %in% columns

  if (!has_resolved_at) {
    return(invisible(FALSE))
  }

  if (has_worn_on) {
    stop(
      "Recommendations cannot contain both resolved_at and worn_on.",
      call. = FALSE
    )
  }

  recommendations <- db_table_name(connection, "recommendations", config)
  settings <- db_table_name(connection, "app_settings", config)
  history <- db_table_name(connection, "wear_history", config)
  legacy_recommendations <- db_table_name(
    connection,
    "recommendations_resolved_at_legacy",
    config
  )
  legacy_rows <- DBI::dbGetQuery(
    connection,
    sprintf("SELECT * FROM %s", recommendations)
  )
  worn_rows <- legacy_rows$status == "worn"
  worn_on <- rep(as.Date(NA), nrow(legacy_rows))

  if (any(worn_rows)) {
    worn_on[worn_rows] <- as.Date(
      legacy_rows$resolved_at[worn_rows],
      tz = config$display_timezone
    )
  }

  legacy_rows$resolved_at <- NULL
  legacy_rows$worn_on <- worn_on
  legacy_rows <- legacy_rows[c(
    "recommendation_id",
    "selection_cycle_id",
    "outfit_id",
    "catalog_publication_id",
    "weather_mode",
    "effective_cooldown",
    "status",
    "created_at",
    "worn_on",
    "top_item_name",
    "top_img_url",
    "bottom_item_name",
    "bottom_img_url",
    "shoes_item_name",
    "shoes_img_url"
  )]

  DBI::dbWithTransaction(connection, {
    DBI::dbExecute(
      connection,
      paste(
        "CREATE TEMP TABLE app_settings_worn_on_migration AS",
        sprintf("SELECT * FROM %s", settings)
      )
    )
    DBI::dbExecute(connection, sprintf("DROP VIEW %s", history))
    DBI::dbExecute(connection, sprintf("DROP TABLE %s", settings))
    DBI::dbExecute(
      connection,
      sprintf(
        "ALTER TABLE %s RENAME TO recommendations_resolved_at_legacy",
        recommendations
      )
    )

    DBI::dbExecute(connection, schema_sql)
    DBI::dbAppendTable(
      connection,
      DBI::Id(
        schema = config$database_schema,
        table = "recommendations"
      ),
      legacy_rows
    )
    DBI::dbExecute(connection, sprintf("DELETE FROM %s", settings))
    DBI::dbExecute(
      connection,
      sprintf(
        paste(
          "INSERT INTO %s",
          "(settings_id, weather_mode, active_recommendation_id,",
          "state_version, updated_at)",
          "SELECT settings_id, weather_mode, active_recommendation_id,",
          "state_version, updated_at",
          "FROM app_settings_worn_on_migration"
        ),
        settings
      )
    )
    DBI::dbExecute(connection, sprintf("DROP TABLE %s", legacy_recommendations))
    DBI::dbExecute(
      connection,
      "DROP TABLE app_settings_worn_on_migration"
    )
  })

  invisible(TRUE)
}

initialize_database_schema <- function(
  connection,
  schema_path = file.path("db", "schema.sql"),
  config = clothes_app_config
) {
  schema_sql <- read_schema_sql(schema_path)
  migrate_recommendation_worn_date(
    connection,
    schema_sql,
    config
  )
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

  recommendation_columns <- database_column_names(
    connection,
    "recommendations",
    config
  )

  list(
    objects = objects,
    settings = settings,
    recommendation_columns = recommendation_columns
  )
}
