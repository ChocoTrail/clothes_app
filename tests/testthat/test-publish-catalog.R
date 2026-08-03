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

test_that("plan rejects component changes for published outfit IDs", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  seed_test_catalog(connection)
  catalog <- read_published_catalog(connection)
  outfits <- read_published_outfits(connection) |>
    dplyr::mutate(top_item_id = "different_top")

  plan <- build_catalog_publish_plan(connection, catalog, outfits)

  expect_true(catalog_has_errors(plan))
  expect_true("top_one--bottom_one--shoes_one" %in% plan$issues$value)
  expect_match(
    plan$issues$message[
      plan$issues$value == "top_one--bottom_one--shoes_one"
    ],
    "component IDs cannot change"
  )
})

test_that("catalog publication writes one complete publication", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  catalog <- compatibility_catalog_fixture()
  outfits <- generate_outfits(catalog)

  receipt <- publish_catalog_transaction(
    connection,
    catalog,
    outfits
  )

  published_items <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT catalog_publication_id, count(*) AS rows",
      "FROM clothes_app.clothing_items",
      "GROUP BY catalog_publication_id"
    )
  )
  published_outfits <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT catalog_publication_id, count(*) AS rows",
      "FROM clothes_app.outfits",
      "GROUP BY catalog_publication_id"
    )
  )

  expect_match(
    receipt$publication_id,
    "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
  )
  expect_equal(
    published_items$catalog_publication_id,
    receipt$publication_id
  )
  expect_equal(published_items$rows, 6)
  expect_equal(
    published_outfits$catalog_publication_id,
    receipt$publication_id
  )
  expect_equal(published_outfits$rows, 8)
})

test_that("catalog publication leaves protected application state untouched", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  seed_test_catalog(connection)
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO clothes_app.recommendations",
      "(recommendation_id, selection_cycle_id, outfit_id, catalog_publication_id,",
      "weather_mode, effective_cooldown, status, resolved_at,",
      "top_item_name, top_img_url, bottom_item_name, bottom_img_url,",
      "shoes_item_name, shoes_img_url)",
      "VALUES",
      "('recommendation-one', 'cycle-one', 'top_one--bottom_one--shoes_one',",
      "'publication-one', 'warm', 5, 'worn', current_timestamp,",
      "'Top One', 'https://example.com/top.png',",
      "'Bottom One', 'https://example.com/bottom.png',",
      "'Shoes One', 'https://example.com/shoes.png')"
    )
  )
  settings_before <- DBI::dbGetQuery(
    connection,
    "SELECT * FROM clothes_app.app_settings"
  )
  recommendations_before <- DBI::dbGetQuery(
    connection,
    "SELECT * FROM clothes_app.recommendations"
  )
  catalog <- read_published_catalog(connection) |>
    dplyr::mutate(
      item_name = dplyr::if_else(
        item_id == "top_one",
        "Updated Top",
        item_name
      )
    )

  publish_catalog_transaction(
    connection,
    catalog,
    generate_outfits(catalog),
    publication_id = "publication-two"
  )

  settings_after <- DBI::dbGetQuery(
    connection,
    "SELECT * FROM clothes_app.app_settings"
  )
  recommendations_after <- DBI::dbGetQuery(
    connection,
    "SELECT * FROM clothes_app.recommendations"
  )
  expect_identical(settings_after, settings_before)
  expect_identical(recommendations_after, recommendations_before)
  expect_equal(
    DBI::dbGetQuery(
      connection,
      paste(
        "SELECT item_name FROM clothes_app.clothing_items",
        "WHERE item_id = 'top_one'"
      )
    )$item_name,
    "Updated Top"
  )
})

test_that("catalog publication rolls back both tables after a write failure", {
  connection <- new_test_database()
  on.exit(db_disconnect(connection), add = TRUE)
  catalog <- compatibility_catalog_fixture()
  invalid_outfits <- generate_outfits(catalog) |>
    dplyr::mutate(
      shoes_item_id = dplyr::if_else(
        dplyr::row_number() == 1L,
        "missing_shoes",
        shoes_item_id
      )
    )
  settings_before <- DBI::dbGetQuery(
    connection,
    "SELECT * FROM clothes_app.app_settings"
  )

  expect_error(
    publish_catalog_transaction(
      connection,
      catalog,
      invalid_outfits,
      publication_id = "publication-fails"
    ),
    "foreign key|constraint",
    ignore.case = TRUE
  )

  expect_equal(
    DBI::dbGetQuery(
      connection,
      "SELECT count(*) AS rows FROM clothes_app.clothing_items"
    )$rows,
    0
  )
  expect_equal(
    DBI::dbGetQuery(
      connection,
      "SELECT count(*) AS rows FROM clothes_app.outfits"
    )$rows,
    0
  )
  expect_identical(
    DBI::dbGetQuery(connection, "SELECT * FROM clothes_app.app_settings"),
    settings_before
  )
})
