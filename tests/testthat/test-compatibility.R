test_that("generator creates every top-bottom-shoes combination", {
  outfits <- generate_outfits(compatibility_catalog_fixture())

  expect_equal(nrow(outfits), 8L)
  expect_equal(dplyr::n_distinct(outfits$outfit_id), 8L)
  expect_equal(
    names(outfits),
    c(
      "outfit_id",
      "top_item_id",
      "bottom_item_id",
      "shoes_item_id",
      "is_compatible",
      "exclusion_reason"
    )
  )
})

test_that("black tops are excluded with darkblue bottoms", {
  outfits <- generate_outfits(compatibility_catalog_fixture())
  excluded <- outfits |>
    dplyr::filter(
      top_item_id == "top_black",
      bottom_item_id == "bottom_darkblue"
    )

  expect_equal(nrow(excluded), 2L)
  expect_true(all(!excluded$is_compatible))
  expect_true(all(
    excluded$exclusion_reason ==
      compatibility_reasons$black_top_darkblue_bottom
  ))
})

test_that("gray shoes are excluded with khaki bottoms", {
  outfits <- generate_outfits(compatibility_catalog_fixture())
  excluded <- outfits |>
    dplyr::filter(
      shoes_item_id == "shoes_gray",
      bottom_item_id == "bottom_khaki"
    )

  expect_equal(nrow(excluded), 2L)
  expect_true(all(!excluded$is_compatible))
  expect_true(all(
    excluded$exclusion_reason ==
      compatibility_reasons$gray_shoes_khaki_bottom
  ))
})

test_that("silver and gray tops are excluded with khaki and gray bottoms", {
  catalog <- compatibility_catalog_fixture() |>
    dplyr::bind_rows(
      tibble::tribble(
        ~item_id, ~item_name, ~category, ~color, ~season, ~img_url, ~active,
        "top_silver", "Silver Top", "top", "silver", "all", "https://example.com/top-silver.png", TRUE,
        "top_gray", "Gray Top", "top", "gray", "all", "https://example.com/top-gray.png", TRUE,
        "bottom_gray", "Gray Bottom", "bottom", "gray", "all", "https://example.com/bottom-gray.png", TRUE
      )
    )

  excluded <- generate_outfits(catalog) |>
    dplyr::filter(
      top_item_id %in% c("top_silver", "top_gray"),
      bottom_item_id %in% c("bottom_khaki", "bottom_gray")
    )

  expect_equal(nrow(excluded), 8L)
  expect_true(all(!excluded$is_compatible))
  expect_true(all(
    excluded$exclusion_reason ==
      compatibility_reasons$silver_or_gray_top_khaki_or_gray_bottom
  ))
})

test_that("unaffected combinations remain compatible", {
  outfits <- generate_outfits(compatibility_catalog_fixture())
  unaffected <- outfits |>
    dplyr::filter(
      top_item_id == "top_white",
      bottom_item_id == "bottom_darkblue",
      shoes_item_id == "shoes_black"
    )

  expect_true(unaffected$is_compatible)
  expect_true(is.na(unaffected$exclusion_reason))
})

test_that("new top and bottom colors do not exclude other pairings", {
  catalog <- compatibility_catalog_fixture() |>
    dplyr::bind_rows(
      tibble::tribble(
        ~item_id, ~item_name, ~category, ~color, ~season, ~img_url, ~active,
        "top_silver", "Silver Top", "top", "silver", "all", "https://example.com/top-silver.png", TRUE,
        "bottom_gray", "Gray Bottom", "bottom", "gray", "all", "https://example.com/bottom-gray.png", TRUE
      )
    )

  outfits <- generate_outfits(catalog)
  silver_with_darkblue <- outfits |>
    dplyr::filter(
      top_item_id == "top_silver",
      bottom_item_id == "bottom_darkblue",
      shoes_item_id == "shoes_black"
    )
  white_with_gray <- outfits |>
    dplyr::filter(
      top_item_id == "top_white",
      bottom_item_id == "bottom_gray",
      shoes_item_id == "shoes_black"
    )

  expect_true(silver_with_darkblue$is_compatible)
  expect_true(white_with_gray$is_compatible)
})

test_that("outfit IDs are stable across catalog row order", {
  catalog <- compatibility_catalog_fixture()
  reversed_catalog <- catalog[nrow(catalog):1L, ]

  original_outfits <- generate_outfits(catalog)
  reversed_outfits <- generate_outfits(reversed_catalog)

  expect_identical(original_outfits, reversed_outfits)
})

test_that("inactive items remain in the generated catalog", {
  catalog <- compatibility_catalog_fixture() |>
    dplyr::mutate(
      active = dplyr::if_else(item_id == "top_black", FALSE, active)
    )

  outfits <- generate_outfits(catalog)

  expect_true("top_black" %in% outfits$top_item_id)
  expect_equal(nrow(outfits), 8L)
})
