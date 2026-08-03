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
  outfit_identity_changes <- outfit_comparison$joined |>
    dplyr::filter(
      top_item_id_incoming != top_item_id_existing
      | bottom_item_id_incoming != bottom_item_id_existing
      | shoes_item_id_incoming != shoes_item_id_existing
    )

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
    ),
    purrr::map_dfr(
      outfit_identity_changes$outfit_id,
      ~ new_catalog_issue(
        "error",
        NA_integer_,
        "outfit_id",
        .x,
        "Published outfit component IDs cannot change for an existing outfit ID."
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

new_catalog_publication_id <- function(connection) {
  DBI::dbGetQuery(
    connection,
    "SELECT CAST(uuid() AS VARCHAR) AS catalog_publication_id"
  )$catalog_publication_id[[1]]
}

publication_timestamp <- function(connection) {
  DBI::dbGetQuery(
    connection,
    "SELECT current_timestamp AS published_at"
  )$published_at[[1]]
}

stage_table_name <- function(connection, table) {
  as.character(DBI::dbQuoteIdentifier(connection, table))
}

create_catalog_staging_tables <- function(
  connection,
  config = clothes_app_config
) {
  items_stage <- stage_table_name(connection, "catalog_items_staging")
  outfits_stage <- stage_table_name(connection, "catalog_outfits_staging")

  DBI::dbExecute(
    connection,
    sprintf("DROP TABLE IF EXISTS %s", outfits_stage)
  )
  DBI::dbExecute(
    connection,
    sprintf("DROP TABLE IF EXISTS %s", items_stage)
  )
  DBI::dbExecute(
    connection,
    sprintf(
      "CREATE TEMP TABLE %s AS SELECT * FROM %s WHERE FALSE",
      items_stage,
      catalog_table_name(connection, "clothing_items", config)
    )
  )
  DBI::dbExecute(
    connection,
    sprintf(
      "CREATE TEMP TABLE %s AS SELECT * FROM %s WHERE FALSE",
      outfits_stage,
      catalog_table_name(connection, "outfits", config)
    )
  )

  invisible(list(items = items_stage, outfits = outfits_stage))
}

update_catalog_from_staging <- function(
  connection,
  staging,
  config = clothes_app_config
) {
  items_table <- catalog_table_name(connection, "clothing_items", config)
  outfits_table <- catalog_table_name(connection, "outfits", config)

  DBI::dbExecute(
    connection,
    sprintf(
      paste(
        "UPDATE %s AS target",
        "SET item_name = stage.item_name,",
        "category = stage.category,",
        "color = stage.color,",
        "season = stage.season,",
        "img_url = stage.img_url,",
        "active = stage.active,",
        "catalog_publication_id = stage.catalog_publication_id,",
        "published_at = stage.published_at",
        "FROM %s AS stage",
        "WHERE target.item_id = stage.item_id"
      ),
      items_table,
      staging$items
    )
  )
  DBI::dbExecute(
    connection,
    sprintf(
      paste(
        "INSERT INTO %s",
        "SELECT stage.* FROM %s AS stage",
        "LEFT JOIN %s AS existing USING (item_id)",
        "WHERE existing.item_id IS NULL"
      ),
      items_table,
      staging$items,
      items_table
    )
  )

  DBI::dbExecute(
    connection,
    sprintf(
      paste(
        "UPDATE %s AS target",
        "SET is_compatible = stage.is_compatible,",
        "exclusion_reason = stage.exclusion_reason,",
        "catalog_publication_id = stage.catalog_publication_id,",
        "published_at = stage.published_at",
        "FROM %s AS stage",
        "WHERE target.outfit_id = stage.outfit_id"
      ),
      outfits_table,
      staging$outfits
    )
  )
  DBI::dbExecute(
    connection,
    sprintf(
      paste(
        "INSERT INTO %s",
        "SELECT stage.* FROM %s AS stage",
        "LEFT JOIN %s AS existing USING (outfit_id)",
        "WHERE existing.outfit_id IS NULL"
      ),
      outfits_table,
      staging$outfits,
      outfits_table
    )
  )

  invisible(NULL)
}

publish_catalog_transaction <- function(
  connection,
  catalog,
  outfits,
  publication_id = NULL,
  config = clothes_app_config
) {
  if (is.null(publication_id)) {
    publication_id <- new_catalog_publication_id(connection)
  }

  if (
    length(publication_id) != 1L
    || is.na(publication_id)
    || !nzchar(trimws(publication_id))
  ) {
    stop("Catalog publication ID must be one non-empty value.", call. = FALSE)
  }

  receipt <- DBI::dbWithTransaction(connection, {
    plan <- build_catalog_publish_plan(connection, catalog, outfits, config)

    if (catalog_has_errors(plan)) {
      stop(
        "Catalog publication failed its existing-catalog checks.",
        call. = FALSE
      )
    }

    published_at <- publication_timestamp(connection)
    catalog_rows <- catalog |>
      dplyr::mutate(
        catalog_publication_id = publication_id,
        published_at = published_at
      )
    outfit_rows <- outfits |>
      dplyr::mutate(
        catalog_publication_id = publication_id,
        published_at = published_at
      )

    staging <- create_catalog_staging_tables(connection, config)
    DBI::dbAppendTable(connection, "catalog_items_staging", catalog_rows)
    DBI::dbAppendTable(connection, "catalog_outfits_staging", outfit_rows)

    update_catalog_from_staging(connection, staging, config)

    DBI::dbExecute(
      connection,
      sprintf("DROP TABLE %s", staging$outfits)
    )
    DBI::dbExecute(
      connection,
      sprintf("DROP TABLE %s", staging$items)
    )

    list(
      publication_id = publication_id,
      published_at = published_at,
      summary = plan$summary
    )
  })

  invisible(receipt)
}
