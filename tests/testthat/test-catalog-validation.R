valid_catalog_fixture <- function() {
  tibble::tribble(
    ~item_id, ~item_name, ~category, ~color, ~season, ~img_url, ~active,
    "top_one", "Top One", "top", "black", "all", "https://example.com/top.png", "TRUE",
    "bottom_one", "Bottom One", "bottom", "darkblue", "cold", "https://example.com/bottom.png", "TRUE",
    "shoes_one", "Shoes One", "shoes", "gray", "all", "https://example.com/shoes.png", "FALSE",
    "shoes_two", "Shoes Two", "shoes", "black", "warm", "https://example.com/shoes-two.png", "TRUE"
  )
}

test_that("valid catalog is normalized after validation", {
  validation <- validate_catalog(valid_catalog_fixture())

  expect_false(catalog_has_errors(validation))
  expect_equal(nrow(validation$issues), 0L)
  expect_identical(names(validation$data), catalog_source_columns())
  expect_type(validation$data$active, "logical")
  expect_equal(validation$data$color[2], "darkblue")
})

test_that("catalog requires the exact source columns", {
  missing_column <- valid_catalog_fixture() |>
    dplyr::select(-season)
  extra_column <- valid_catalog_fixture() |>
    dplyr::mutate(notes = "extra")

  missing_validation <- validate_catalog(missing_column)
  extra_validation <- validate_catalog(extra_column)

  expect_true(catalog_has_errors(missing_validation))
  expect_equal(missing_validation$issues$column, "season")
  expect_match(missing_validation$issues$message, "missing")
  expect_true(catalog_has_errors(extra_validation))
  expect_equal(extra_validation$issues$column, "notes")
  expect_match(extra_validation$issues$message, "Unexpected")
})

test_that("catalog reports row-level contract violations", {
  invalid_catalog <- valid_catalog_fixture()
  invalid_catalog$item_id[2] <- "Top One"
  invalid_catalog$item_id[3] <- "top_one"
  invalid_catalog$category[2] <- "pants"
  invalid_catalog$color[2] <- "Dark Blue"
  invalid_catalog$season[2] <- "winter"
  invalid_catalog$img_url[2] <- "http://example.com/bottom.png"
  invalid_catalog$active[2] <- "yes"

  validation <- validate_catalog(invalid_catalog)

  expect_true(catalog_has_errors(validation))
  expect_null(validation$data)
  expect_setequal(
    unique(validation$issues$column),
    c("item_id", "category", "color", "season", "img_url", "active")
  )
  expect_true(all(validation$issues$sheet_row >= 2L, na.rm = TRUE))
})

test_that("every category must have an active item", {
  catalog <- valid_catalog_fixture() |>
    dplyr::mutate(
      active = dplyr::if_else(category == "shoes", "FALSE", active)
    )

  validation <- validate_catalog(catalog)
  category_issue <- validation$issues |>
    dplyr::filter(is.na(sheet_row), value == "shoes")

  expect_true(catalog_has_errors(validation))
  expect_equal(nrow(category_issue), 1L)
  expect_match(category_issue$message, "No active shoes")
})

test_that("Google image URLs must use the browser-safe form", {
  invalid_urls <- c(
    "https://drive.google.com/file/d/file-id/view?usp=sharing",
    "https://drive.google.com/drive/folders/folder-id",
    "https://drive.google.com/uc?export=view&id=file-id"
  )

  for (invalid_url in invalid_urls) {
    catalog <- valid_catalog_fixture()
    catalog$img_url[[1]] <- invalid_url
    validation <- validate_catalog(catalog)
    image_issue <- validation$issues |>
      dplyr::filter(.data$sheet_row == 2L, .data$column == "img_url")

    expect_true(catalog_has_errors(validation))
    expect_equal(nrow(image_issue), 1L)
    expect_match(image_issue$message, "browser-safe Google image URL")
  }

  catalog <- valid_catalog_fixture()
  catalog$img_url[[1]] <- paste0(
    "https://lh3.googleusercontent.com/d/",
    "13N-TfTOzv-tWJj1Hjmq6zRlNywKP714t=w1200"
  )

  expect_false(catalog_has_errors(validate_catalog(catalog)))
})
