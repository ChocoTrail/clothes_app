compatibility_reasons <- list(
  black_top_darkblue_bottom = "black_top_with_darkblue_bottom",
  silver_or_gray_top_khaki_or_gray_bottom =
    "silver_or_gray_top_with_khaki_or_gray_bottom",
  gray_shoes_khaki_bottom = "gray_shoes_with_khaki_bottom"
)

catalog_items_for_outfits <- function(catalog, item_category, prefix) {
  catalog |>
    dplyr::filter(category == item_category) |>
    dplyr::transmute(
      item_id,
      color,
      active
    ) |>
    dplyr::arrange(item_id) |>
    dplyr::rename_with(
      ~ paste0(prefix, "_", .x),
      dplyr::everything()
    )
}

generate_outfits <- function(catalog) {
  tops <- catalog_items_for_outfits(catalog, "top", "top")
  bottoms <- catalog_items_for_outfits(catalog, "bottom", "bottom")
  shoes <- catalog_items_for_outfits(catalog, "shoes", "shoes")

  tidyr::crossing(tops, bottoms, shoes) |>
    dplyr::mutate(
      outfit_id = paste(
        top_item_id,
        bottom_item_id,
        shoes_item_id,
        sep = "--"
      ),
      exclusion_reason = dplyr::case_when(
        top_color == "black" & bottom_color == "darkblue" ~
          compatibility_reasons$black_top_darkblue_bottom,
        top_color %in% c("silver", "gray") &
          bottom_color %in% c("khaki", "gray") ~
          compatibility_reasons$silver_or_gray_top_khaki_or_gray_bottom,
        shoes_color == "gray" & bottom_color == "khaki" ~
          compatibility_reasons$gray_shoes_khaki_bottom,
        TRUE ~ NA_character_
      ),
      is_compatible = is.na(exclusion_reason)
    ) |>
    dplyr::select(
      outfit_id,
      top_item_id,
      bottom_item_id,
      shoes_item_id,
      is_compatible,
      exclusion_reason
    )
}

summarize_compatibility <- function(outfits) {
  outfits |>
    dplyr::mutate(
      result = dplyr::if_else(
        is_compatible,
        "compatible",
        exclusion_reason
      )
    ) |>
    dplyr::count(result, name = "outfits") |>
    dplyr::arrange(dplyr::desc(result == "compatible"), result)
}
