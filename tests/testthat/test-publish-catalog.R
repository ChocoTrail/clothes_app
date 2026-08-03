test_that("empty database plan reports all catalog rows as new", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  catalog <- compatibility_catalog_fixture()
  outfits <- generate_outfits(catalog)

  plan <- build_catalog_publish_plan(connection, catalog, outfits)

  expect_false(catalog_has_errors(plan))
  expect_equal(plan$summary$existing, c(0, 0))
  expect_equal(plan$summary$incoming, c(6, 8))
  expect_equal(plan$summary$new, c(6, 8))
  expect_equal(plan$summary$updated, c(0, 0))
  expect_equal(plan$protected_counts$rows, c(1, 0))
})

test_that("unchanged database plan reports stable rows", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  seed_test_catalog(connection)
  catalog <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT item_id, item_name, category, color, season, img_url, active",
      "FROM clothes_app.clothing_items",
      "ORDER BY item_id"
    )
  ) |>
    tibble::as_tibble()
  outfits <- generate_outfits(catalog)

  plan <- build_catalog_publish_plan(connection, catalog, outfits)

  expect_false(catalog_has_errors(plan))
  expect_equal(plan$summary$new, c(0, 0))
  expect_equal(plan$summary$updated, c(0, 0))
  expect_equal(plan$summary$unchanged, c(3, 1))
})

test_that("plan rejects disappeared published items", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  seed_test_catalog(connection)
  catalog <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT item_id, item_name, category, color, season, img_url, active",
      "FROM clothes_app.clothing_items",
      "WHERE item_id <> 'shoes_one'"
    )
  ) |>
    tibble::as_tibble()
  outfits <- tibble::tibble(
    outfit_id = character(),
    top_item_id = character(),
    bottom_item_id = character(),
    shoes_item_id = character(),
    is_compatible = logical(),
    exclusion_reason = character()
  )

  plan <- build_catalog_publish_plan(connection, catalog, outfits)

  expect_true(catalog_has_errors(plan))
  expect_true("shoes_one" %in% plan$issues$value)
  expect_match(
    plan$issues$message[plan$issues$value == "shoes_one"],
    "restore it"
  )
})

test_that("plan rejects category changes for published IDs", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  seed_test_catalog(connection)
  catalog <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT item_id, item_name, category, color, season, img_url, active",
      "FROM clothes_app.clothing_items",
      "ORDER BY item_id"
    )
  ) |>
    tibble::as_tibble() |>
    dplyr::mutate(
      category = dplyr::if_else(
        item_id == "top_one",
        "bottom",
        category
      )
    )
  outfits <- read_published_outfits(connection)

  plan <- build_catalog_publish_plan(connection, catalog, outfits)

  expect_true(catalog_has_errors(plan))
  expect_true("top_one" %in% plan$issues$value)
  expect_match(
    plan$issues$message[plan$issues$value == "top_one"],
    "cannot change"
  )
})

test_that("plan identifies mutable catalog updates", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  seed_test_catalog(connection)
  catalog <- read_published_catalog(connection) |>
    dplyr::mutate(
      item_name = dplyr::if_else(
        item_id == "top_one",
        "Updated Top",
        item_name
      )
    )
  outfits <- generate_outfits(catalog)

  plan <- build_catalog_publish_plan(connection, catalog, outfits)

  expect_false(catalog_has_errors(plan))
  expect_equal(plan$summary$updated, c(1, 0))
  expect_equal(plan$summary$unchanged, c(2, 1))
})
