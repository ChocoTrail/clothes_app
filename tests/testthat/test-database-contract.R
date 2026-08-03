test_that("schema creates the designed objects and warm singleton", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)

  contract <- database_contract_summary(connection)

  expect_setequal(
    contract$objects$table_name,
    c(
      "app_settings",
      "clothing_items",
      "outfits",
      "recommendations",
      "wear_history"
    )
  )
  expect_equal(contract$settings$settings_id, "singleton")
  expect_equal(contract$settings$weather_mode, "warm")
  expect_true(is.na(contract$settings$active_recommendation_id))
  expect_equal(contract$settings$state_version, 0)
})

test_that("schema constraints reject invalid controlled values", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)

  expect_error(
    DBI::dbExecute(
      connection,
      paste(
        "INSERT INTO clothes_app.clothing_items",
        "(item_id, item_name, category, color, season, img_url, active, catalog_publication_id)",
        "VALUES ('bad-item', 'Bad Item', 'hat', 'black', 'all', 'https://example.com/item.png', TRUE, 'publication-one')"
      )
    ),
    "CHECK constraint"
  )

  expect_error(
    DBI::dbExecute(
      connection,
      "UPDATE clothes_app.app_settings SET weather_mode = 'mild' WHERE settings_id = 'singleton'"
    ),
    "CHECK constraint"
  )

  seed_test_catalog(connection)

  expect_error(
    DBI::dbExecute(
      connection,
      paste(
        "INSERT INTO clothes_app.outfits",
        "(outfit_id, top_item_id, pants_item_id, shoes_item_id, is_compatible, exclusion_reason, catalog_publication_id)",
        "VALUES",
        "('duplicate-outfit', 'top-one', 'pants-one', 'shoes-one', TRUE, NULL, 'publication-one')"
      )
    ),
    "[Dd]uplicate key"
  )

  expect_error(
    DBI::dbExecute(
      connection,
      paste(
        "INSERT INTO clothes_app.recommendations",
        "(recommendation_id, selection_cycle_id, outfit_id, catalog_publication_id, weather_mode, effective_cooldown, status, resolved_at, top_item_name, top_img_url, pants_item_name, pants_img_url, shoes_item_name, shoes_img_url)",
        "VALUES",
        "('invalid-active', 'cycle-one', 'top-one--pants-one--shoes-one', 'publication-one', 'warm', 5, 'active', current_timestamp, 'Top One', 'https://example.com/top.png', 'Pants One', 'https://example.com/pants.png', 'Shoes One', 'https://example.com/shoes.png')"
      )
    ),
    "CHECK constraint"
  )
})

test_that("wear history is derived from worn recommendation snapshots", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  seed_test_catalog(connection)

  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO clothes_app.recommendations",
      "(recommendation_id, selection_cycle_id, outfit_id, catalog_publication_id, weather_mode, effective_cooldown, status, created_at, resolved_at, top_item_name, top_img_url, pants_item_name, pants_img_url, shoes_item_name, shoes_img_url)",
      "VALUES",
      "('recommendation-one', 'cycle-one', 'top-one--pants-one--shoes-one', 'publication-one', 'warm', 5, 'worn', TIMESTAMPTZ '2026-08-03 15:00:00+00', TIMESTAMPTZ '2026-08-03 15:05:00+00', 'Top Snapshot', 'https://example.com/top-snapshot.png', 'Pants Snapshot', 'https://example.com/pants-snapshot.png', 'Shoes Snapshot', 'https://example.com/shoes-snapshot.png')"
    )
  )

  history <- DBI::dbGetQuery(
    connection,
    "SELECT * FROM clothes_app.wear_history"
  )

  expect_equal(nrow(history), 1L)
  expect_equal(history$top_item_name, "Top Snapshot")
  expect_equal(history$pants_item_name, "Pants Snapshot")
  expect_equal(history$shoes_item_name, "Shoes Snapshot")
})

test_that("reinitialization preserves settings and recommendation history", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  seed_test_catalog(connection)

  DBI::dbExecute(
    connection,
    paste(
      "UPDATE clothes_app.app_settings",
      "SET weather_mode = 'cold', state_version = 7",
      "WHERE settings_id = 'singleton'"
    )
  )

  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO clothes_app.recommendations",
      "(recommendation_id, selection_cycle_id, outfit_id, catalog_publication_id, weather_mode, effective_cooldown, status, resolved_at, top_item_name, top_img_url, pants_item_name, pants_img_url, shoes_item_name, shoes_img_url)",
      "VALUES",
      "('recommendation-one', 'cycle-one', 'top-one--pants-one--shoes-one', 'publication-one', 'cold', 5, 'worn', current_timestamp, 'Top One', 'https://example.com/top.png', 'Pants One', 'https://example.com/pants.png', 'Shoes One', 'https://example.com/shoes.png')"
    )
  )

  initialize_database_schema(
    connection,
    file.path(project_root, "db", "schema.sql")
  )

  contract <- database_contract_summary(connection)
  recommendation_count <- DBI::dbGetQuery(
    connection,
    "SELECT count(*) AS n FROM clothes_app.recommendations"
  )

  expect_equal(contract$settings$weather_mode, "cold")
  expect_equal(contract$settings$state_version, 7)
  expect_equal(recommendation_count$n, 1)
})

test_that("settings persist across a clean disconnect and reconnect", {
  database_path <- tempfile(fileext = ".duckdb")
  on.exit(unlink(database_path), add = TRUE)

  first_connection <- db_connect_local(database_path)
  initialize_database_schema(
    first_connection,
    file.path(project_root, "db", "schema.sql")
  )
  DBI::dbExecute(
    first_connection,
    paste(
      "UPDATE clothes_app.app_settings",
      "SET weather_mode = 'cold', state_version = 1",
      "WHERE settings_id = 'singleton'"
    )
  )
  db_disconnect(first_connection)

  second_connection <- db_connect_local(database_path)
  on.exit(db_disconnect(second_connection), add = TRUE)
  contract <- database_contract_summary(second_connection)

  expect_equal(contract$settings$weather_mode, "cold")
  expect_equal(contract$settings$state_version, 1)
})
