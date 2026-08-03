test_that("choosing saves one active recommendation and snapshots its display", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  seed_test_catalog(connection)

  result <- choose_active_recommendation(
    connection,
    starting_state_version = 0L,
    choose_index = choose_first_index
  )

  expect_true(result$created)
  expect_false(result$stale)
  expect_equal(nrow(result$state$recommendation), 1L)
  expect_equal(result$state$recommendation$status, "active")
  expect_equal(result$state$recommendation$top_item_name, "Top One")
  expect_equal(result$state$recommendation$bottom_item_name, "Bottom One")
  expect_equal(result$state$recommendation$shoes_item_name, "Shoes One")
  expect_equal(result$state$recommendation$effective_cooldown, 5L)
  expect_equal(result$state$settings$state_version, 1)
  expect_equal(
    result$state$settings$active_recommendation_id,
    result$state$recommendation$recommendation_id
  )
})

test_that("repeated choose returns the saved recommendation without duplication", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  seed_test_catalog(connection)
  first_result <- choose_active_recommendation(
    connection,
    starting_state_version = 0L,
    choose_index = choose_first_index
  )

  repeated_result <- choose_active_recommendation(
    connection,
    starting_state_version = 0L,
    choose_index = choose_first_index
  )
  recommendation_count <- DBI::dbGetQuery(
    connection,
    "SELECT count(*) AS rows FROM clothes_app.recommendations"
  )$rows

  expect_false(repeated_result$created)
  expect_true(repeated_result$stale)
  expect_equal(recommendation_count, 1)
  expect_equal(
    repeated_result$state$recommendation$recommendation_id,
    first_result$state$recommendation$recommendation_id
  )
})

test_that("current active recommendation reloads after reconnecting", {
  database_path <- tempfile(fileext = ".duckdb")
  on.exit(unlink(database_path), add = TRUE)
  first_connection <- db_connect_local(database_path)
  initialize_database_schema(
    first_connection,
    file.path(project_root, "db", "schema.sql")
  )
  seed_test_catalog(first_connection)
  created <- choose_active_recommendation(
    first_connection,
    starting_state_version = 0L,
    choose_index = choose_first_index
  )
  db_disconnect(first_connection)

  second_connection <- db_connect_local(database_path)
  on.exit(db_disconnect(second_connection), add = TRUE)
  reloaded <- read_recommendation_state(second_connection)

  expect_equal(
    reloaded$recommendation$recommendation_id,
    created$state$recommendation$recommendation_id
  )
  expect_equal(reloaded$settings$state_version, 1)
})

test_that("choosing with no eligible outfit rolls back cleanly", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  seed_test_catalog(connection)
  DBI::dbExecute(
    connection,
    "UPDATE clothes_app.clothing_items SET active = FALSE"
  )

  expect_error(
    choose_active_recommendation(
      connection,
      starting_state_version = 0L,
      choose_index = choose_first_index
    ),
    "No compatible, active outfits"
  )

  state <- read_recommendation_state(connection)
  expect_true(is.na(state$settings$active_recommendation_id))
  expect_equal(state$settings$state_version, 0)
  expect_equal(
    DBI::dbGetQuery(
      connection,
      "SELECT count(*) AS rows FROM clothes_app.recommendations"
    )$rows,
    0
  )
})
