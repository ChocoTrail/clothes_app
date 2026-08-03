authenticate_catalog_sheet <- function() {
  googlesheets4::gs4_auth(
    email = TRUE,
    scopes = "spreadsheets.readonly"
  )

  invisible(TRUE)
}

read_catalog_sheet <- function(config = clothes_app_config) {
  authenticate_catalog_sheet()

  googlesheets4::read_sheet(
    ss = config$spreadsheet_id,
    sheet = config$spreadsheet_tab,
    col_types = "c",
    .name_repair = "minimal"
  ) |>
    tibble::as_tibble()
}

catalog_table_name <- function(connection, table, config = clothes_app_config) {
  as.character(
    DBI::dbQuoteIdentifier(
      connection,
      DBI::Id(schema = config$database_schema, table = table)
    )
  )
}

read_published_catalog <- function(
  connection,
  config = clothes_app_config
) {
  DBI::dbGetQuery(
    connection,
    sprintf(
      paste(
        "SELECT item_id, item_name, category, color, season, img_url, active",
        "FROM %s",
        "ORDER BY item_id"
      ),
      catalog_table_name(connection, "clothing_items", config)
    )
  ) |>
    tibble::as_tibble()
}

read_published_outfits <- function(
  connection,
  config = clothes_app_config
) {
  DBI::dbGetQuery(
    connection,
    sprintf(
      paste(
        "SELECT outfit_id, top_item_id, bottom_item_id, shoes_item_id,",
        "is_compatible, exclusion_reason",
        "FROM %s",
        "ORDER BY outfit_id"
      ),
      catalog_table_name(connection, "outfits", config)
    )
  ) |>
    tibble::as_tibble()
}

joined_columns_differ <- function(joined, columns) {
  differences <- purrr::map(
    columns,
    function(column) {
      incoming <- joined[[paste0(column, "_incoming")]]
      existing <- joined[[paste0(column, "_existing")]]
      equal <- (
        (is.na(incoming) & is.na(existing))
        | (!is.na(incoming) & !is.na(existing) & incoming == existing)
      )
      !equal
    }
  )

  Reduce(`|`, differences)
}

compare_catalog_rows <- function(incoming, existing, id_column, columns) {
  new_rows <- dplyr::anti_join(incoming, existing, by = id_column)
  missing_rows <- dplyr::anti_join(existing, incoming, by = id_column)
  joined <- dplyr::inner_join(
    incoming,
    existing,
    by = id_column,
    suffix = c("_incoming", "_existing")
  )
  changed <- joined_columns_differ(joined, columns)

  list(
    new_ids = new_rows[[id_column]],
    missing_ids = missing_rows[[id_column]],
    updated_ids = joined[[id_column]][changed],
    unchanged_ids = joined[[id_column]][!changed],
    joined = joined
  )
}

build_catalog_publish_plan <- function(
  connection,
  catalog,
  outfits,
  config = clothes_app_config
) {
  existing_catalog <- read_published_catalog(connection, config)
  existing_outfits <- read_published_outfits(connection, config)

  item_comparison <- compare_catalog_rows(
    catalog,
    existing_catalog,
    "item_id",
    setdiff(catalog_source_columns(), "item_id")
  )
  outfit_comparison <- compare_catalog_rows(
    outfits,
    existing_outfits,
    "outfit_id",
    setdiff(names(outfits), "outfit_id")
  )

  category_changes <- item_comparison$joined |>
    dplyr::filter(category_incoming != category_existing)

  issues <- dplyr::bind_rows(
    new_catalog_issue(
      character(),
      integer(),
      character(),
      character(),
      character()
    ),
    purrr::map_dfr(
      item_comparison$missing_ids,
      ~ new_catalog_issue(
        "error",
        NA_integer_,
        "item_id",
        .x,
        "Previously published item is missing; restore it with active = FALSE."
      )
    ),
    purrr::map_dfr(
      seq_len(nrow(category_changes)),
      function(index) {
        new_catalog_issue(
          "error",
          NA_integer_,
          "category",
          category_changes$item_id[index],
          paste0(
            "Published category cannot change from ",
            category_changes$category_existing[index],
            " to ",
            category_changes$category_incoming[index],
            "."
          )
        )
      }
    ),
    purrr::map_dfr(
      outfit_comparison$missing_ids,
      ~ new_catalog_issue(
        "error",
        NA_integer_,
        "outfit_id",
        .x,
        "Previously generated outfit is absent from the current combination set."
      )
    )
  )

  summary <- tibble::tibble(
    entity = c("clothing_items", "outfits"),
    existing = c(nrow(existing_catalog), nrow(existing_outfits)),
    incoming = c(nrow(catalog), nrow(outfits)),
    new = c(
      length(item_comparison$new_ids),
      length(outfit_comparison$new_ids)
    ),
    updated = c(
      length(item_comparison$updated_ids),
      length(outfit_comparison$updated_ids)
    ),
    unchanged = c(
      length(item_comparison$unchanged_ids),
      length(outfit_comparison$unchanged_ids)
    )
  )

  protected_counts <- tibble::tibble(
    protected_object = c("app_settings", "recommendations"),
    rows = c(
      DBI::dbGetQuery(
        connection,
        sprintf(
          "SELECT count(*) AS n FROM %s",
          catalog_table_name(connection, "app_settings", config)
        )
      )$n,
      DBI::dbGetQuery(
        connection,
        sprintf(
          "SELECT count(*) AS n FROM %s",
          catalog_table_name(connection, "recommendations", config)
        )
      )$n
    )
  )

  list(
    summary = summary,
    protected_counts = protected_counts,
    issues = issues
  )
}
