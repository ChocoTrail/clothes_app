validate_weather_mode <- function(
  weather_mode,
  config = clothes_app_config
) {
  if (
    length(weather_mode) != 1L
    || is.na(weather_mode)
    || !weather_mode %in% config$weather_modes
  ) {
    stop("Weather mode must be warm or cold.", call. = FALSE)
  }

  invisible(weather_mode)
}

read_runtime_catalog <- function(
  connection,
  config = clothes_app_config
) {
  items <- DBI::dbGetQuery(
    connection,
    sprintf(
      paste(
        "SELECT item_id, item_name, category, color, season, img_url,",
        "active, catalog_publication_id, published_at",
        "FROM %s",
        "ORDER BY item_id"
      ),
      db_table_name(connection, "clothing_items", config)
    )
  ) |>
    tibble::as_tibble()

  outfits <- DBI::dbGetQuery(
    connection,
    sprintf(
      paste(
        "SELECT outfit_id, top_item_id, bottom_item_id, shoes_item_id,",
        "is_compatible, exclusion_reason, catalog_publication_id, published_at",
        "FROM %s",
        "ORDER BY outfit_id"
      ),
      db_table_name(connection, "outfits", config)
    )
  ) |>
    tibble::as_tibble()

  list(items = items, outfits = outfits)
}

read_eligible_catalog_outfits <- function(
  connection,
  weather_mode,
  config = clothes_app_config
) {
  catalog <- read_runtime_catalog(connection, config)
  eligible_catalog_outfits(
    catalog$items,
    catalog$outfits,
    weather_mode,
    config
  )
}

catalog_items_for_role <- function(catalog, category, role) {
  catalog |>
    dplyr::filter(.data$category == category) |>
    dplyr::transmute(
      "{role}_item_id" := .data$item_id,
      "{role}_item_name" := .data$item_name,
      "{role}_img_url" := .data$img_url,
      "{role}_season" := .data$season,
      "{role}_active" := .data$active
    )
}

eligible_catalog_outfits <- function(
  catalog,
  outfits,
  weather_mode,
  config = clothes_app_config
) {
  validate_weather_mode(weather_mode, config)

  top_items <- catalog_items_for_role(catalog, "top", "top")
  bottom_items <- catalog_items_for_role(catalog, "bottom", "bottom")
  shoes_items <- catalog_items_for_role(catalog, "shoes", "shoes")

  outfits |>
    dplyr::filter(.data$is_compatible) |>
    dplyr::inner_join(top_items, by = "top_item_id") |>
    dplyr::inner_join(bottom_items, by = "bottom_item_id") |>
    dplyr::inner_join(shoes_items, by = "shoes_item_id") |>
    dplyr::filter(
      .data$top_active,
      .data$bottom_active,
      .data$shoes_active,
      .data$top_season %in% c("all", weather_mode),
      .data$bottom_season %in% c("all", weather_mode),
      .data$shoes_season %in% c("all", weather_mode)
    ) |>
    dplyr::select(
      -dplyr::ends_with("_active"),
      -dplyr::ends_with("_season")
    )
}
