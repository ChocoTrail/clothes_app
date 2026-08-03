test_that("catalog eligibility applies compatibility, active, and weather rules", {
  catalog <- tibble::tribble(
    ~item_id, ~item_name, ~category, ~color, ~season, ~img_url, ~active,
    "top_all", "All Top", "top", "white", "all", "https://example.com/top-all.png", TRUE,
    "top_cold", "Cold Top", "top", "blue", "cold", "https://example.com/top-cold.png", TRUE,
    "top_inactive", "Inactive Top", "top", "blue", "all", "https://example.com/top-inactive.png", FALSE,
    "bottom_all", "All Bottom", "bottom", "black", "all", "https://example.com/bottom.png", TRUE,
    "shoes_warm", "Warm Shoes", "shoes", "white", "warm", "https://example.com/shoes-warm.png", TRUE,
    "shoes_cold", "Cold Shoes", "shoes", "black", "cold", "https://example.com/shoes-cold.png", TRUE
  )
  outfits <- generate_outfits(catalog)
  outfits$is_compatible[outfits$outfit_id == "top_all--bottom_all--shoes_warm"] <- FALSE

  warm_outfits <- eligible_catalog_outfits(catalog, outfits, "warm")
  cold_outfits <- eligible_catalog_outfits(catalog, outfits, "cold")

  expect_equal(nrow(warm_outfits), 0L)
  expect_setequal(
    cold_outfits$outfit_id,
    c(
      "top_all--bottom_all--shoes_cold",
      "top_cold--bottom_all--shoes_cold"
    )
  )
  expect_true(all(cold_outfits$top_item_id != "top_inactive"))
})

test_that("invalid weather modes are rejected", {
  expect_error(
    eligible_catalog_outfits(
      compatibility_catalog_fixture(),
      generate_outfits(compatibility_catalog_fixture()),
      "mild"
    ),
    "warm or cold"
  )
})

recommendation_outfit_fixture <- function() {
  tibble::tribble(
    ~outfit_id, ~top_item_id, ~bottom_item_id, ~shoes_item_id,
    "a_one", "top_a", "bottom_one", "shoes_one",
    "a_two", "top_a", "bottom_two", "shoes_one",
    "a_three", "top_a", "bottom_three", "shoes_one",
    "b_one", "top_b", "bottom_one", "shoes_one",
    "c_one", "top_c", "bottom_one", "shoes_one",
    "d_one", "top_d", "bottom_one", "shoes_one",
    "e_one", "top_e", "bottom_one", "shoes_one",
    "f_one", "top_f", "bottom_one", "shoes_one"
  )
}

test_that("five-wear cooldown excludes recently worn tops", {
  result <- select_recommended_outfit(
    recommendation_outfit_fixture(),
    worn_top_ids = c("top_a", "top_b", "top_c", "top_d", "top_e"),
    choose_index = choose_first_index
  )

  expect_equal(result$effective_cooldown, 5L)
  expect_equal(result$outfit$top_item_id, "top_f")
})

test_that("cooldown progressively relaxes until a candidate exists", {
  outfits <- recommendation_outfit_fixture() |>
    dplyr::filter(.data$top_item_id == "top_e")

  result <- select_recommended_outfit(
    outfits,
    worn_top_ids = c("top_a", "top_b", "top_c", "top_d", "top_e"),
    choose_index = choose_first_index
  )

  expect_equal(result$effective_cooldown, 4L)
  expect_equal(result$outfit$top_item_id, "top_e")
})

test_that("cooldown can relax to zero", {
  outfits <- recommendation_outfit_fixture() |>
    dplyr::filter(.data$top_item_id == "top_a")

  result <- select_recommended_outfit(
    outfits,
    worn_top_ids = "top_a",
    choose_index = choose_first_index
  )

  expect_equal(result$effective_cooldown, 0L)
  expect_equal(result$outfit$outfit_id, "a_one")
})

test_that("rerolls retain the cycle's effective cooldown", {
  outfits <- recommendation_outfit_fixture() |>
    dplyr::filter(.data$top_item_id %in% c("top_d", "top_e"))

  result <- select_recommended_outfit(
    outfits,
    worn_top_ids = c("top_a", "top_b", "top_c", "top_d", "top_e"),
    effective_cooldown = 4L,
    choose_index = choose_first_index
  )

  expect_equal(result$effective_cooldown, 4L)
  expect_equal(result$outfit$top_item_id, "top_e")
})

test_that("rerolls exclude shown combinations while any unseen remain", {
  outfits <- recommendation_outfit_fixture() |>
    dplyr::filter(.data$top_item_id %in% c("top_a", "top_b"))

  result <- select_recommended_outfit(
    outfits,
    shown_outfit_ids = c("a_one", "a_two", "a_three"),
    effective_cooldown = 5L,
    choose_index = choose_first_index
  )

  expect_true(result$used_unseen_pool)
  expect_equal(result$outfit$outfit_id, "b_one")
})

test_that("rerolls reuse the full pool after all combinations were shown", {
  outfits <- recommendation_outfit_fixture() |>
    dplyr::filter(.data$top_item_id %in% c("top_a", "top_b"))

  result <- select_recommended_outfit(
    outfits,
    shown_outfit_ids = outfits$outfit_id,
    effective_cooldown = 5L,
    choose_index = choose_first_index
  )

  expect_false(result$used_unseen_pool)
  expect_equal(result$outfit$outfit_id, "a_one")
})

test_that("selection chooses a top before one of its combinations", {
  outfits <- recommendation_outfit_fixture() |>
    dplyr::filter(.data$top_item_id %in% c("top_a", "top_b"))
  candidate_counts <- integer()
  recording_chooser <- function(n, size) {
    candidate_counts <<- c(candidate_counts, n)
    1L
  }

  result <- select_recommended_outfit(
    outfits,
    effective_cooldown = 5L,
    choose_index = recording_chooser
  )

  expect_equal(candidate_counts, c(2L, 3L))
  expect_equal(result$outfit$outfit_id, "a_one")
})

test_that("one eligible outfit repeats safely on reroll", {
  outfit <- recommendation_outfit_fixture() |>
    dplyr::filter(.data$outfit_id == "a_one")

  result <- select_recommended_outfit(
    outfit,
    shown_outfit_ids = "a_one",
    effective_cooldown = 5L,
    choose_index = choose_first_index
  )

  expect_false(result$used_unseen_pool)
  expect_equal(result$outfit$outfit_id, "a_one")
})

test_that("empty eligible sets return a clear error", {
  expect_error(
    select_recommended_outfit(recommendation_outfit_fixture()[0, ]),
    "No compatible, active outfits"
  )
})
