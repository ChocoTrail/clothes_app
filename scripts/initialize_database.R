#!/usr/bin/env Rscript

source(file.path("R", "config.R"))
source(file.path("R", "database.R"))

arguments <- commandArgs(trailingOnly = TRUE)
use_local_database <- identical(arguments, "--local")

if (length(arguments) > 0L && !use_local_database) {
  stop(
    "Usage: Rscript scripts/initialize_database.R [--local]",
    call. = FALSE
  )
}

connection <- if (use_local_database) {
  message("Initializing a temporary local DuckDB database...")
  db_connect_local()
} else {
  message("Connecting to MotherDuck database choco_trail...")
  db_connect_motherduck()
}

on.exit(db_disconnect(connection), add = TRUE)

initialize_database_schema(connection)
contract <- database_contract_summary(connection)

message("Database schema is initialized.")
print(contract$objects, row.names = FALSE)
print(contract$settings, row.names = FALSE)
