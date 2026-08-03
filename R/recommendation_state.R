read_recommendation_state <- function(
  connection,
  config = clothes_app_config
) {
  settings <- DBI::dbGetQuery(
    connection,
    sprintf(
      paste(
        "SELECT settings_id, weather_mode, active_recommendation_id,",
        "state_version, updated_at",
        "FROM %s",
        "WHERE settings_id = ?"
      ),
      db_table_name(connection, "app_settings", config)
    ),
    params = list(config$settings_id)
  ) |>
    tibble::as_tibble()

  if (nrow(settings) != 1L) {
    stop("The singleton application settings row is missing.", call. = FALSE)
  }

  active_id <- settings$active_recommendation_id[[1]]
  recommendation <- if (is.na(active_id)) {
    tibble::tibble()
  } else {
    DBI::dbGetQuery(
      connection,
      sprintf(
        "SELECT * FROM %s WHERE recommendation_id = ?",
        db_table_name(connection, "recommendations", config)
      ),
      params = list(active_id)
    ) |>
      tibble::as_tibble()
  }

  if (!is.na(active_id) && nrow(recommendation) != 1L) {
    stop(
      "The active recommendation pointer does not resolve to one row.",
      call. = FALSE
    )
  }

  list(settings = settings, recommendation = recommendation)
}

read_recent_worn_top_ids <- function(
  connection,
  maximum_cooldown = 5L,
  config = clothes_app_config
) {
  DBI::dbGetQuery(
    connection,
    sprintf(
      paste(
        "SELECT outfits.top_item_id",
        "FROM %s AS recommendations",
        "JOIN %s AS outfits USING (outfit_id)",
        "WHERE recommendations.status = 'worn'",
        "ORDER BY recommendations.resolved_at DESC,",
        "recommendations.recommendation_id DESC",
        "LIMIT ?"
      ),
      db_table_name(connection, "recommendations", config),
      db_table_name(connection, "outfits", config)
    ),
    params = list(as.integer(maximum_cooldown))
  )$top_item_id
}

same_active_recommendation <- function(current_id, starting_id) {
  current_missing <- length(current_id) == 0L || is.na(current_id)
  starting_missing <- length(starting_id) == 0L || is.na(starting_id)

  if (current_missing || starting_missing) {
    return(current_missing && starting_missing)
  }

  identical(as.character(current_id), as.character(starting_id))
}

insert_active_recommendation <- function(
  connection,
  selection,
  recommendation_id,
  selection_cycle_id,
  weather_mode,
  config = clothes_app_config
) {
  outfit <- selection$outfit

  DBI::dbExecute(
    connection,
    sprintf(
      paste(
        "INSERT INTO %s",
        "(recommendation_id, selection_cycle_id, outfit_id,",
        "catalog_publication_id, weather_mode, effective_cooldown, status,",
        "top_item_name, top_img_url, bottom_item_name, bottom_img_url,",
        "shoes_item_name, shoes_img_url)",
        "VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?)"
      ),
      db_table_name(connection, "recommendations", config)
    ),
    params = list(
      recommendation_id,
      selection_cycle_id,
      outfit$outfit_id[[1]],
      outfit$catalog_publication_id[[1]],
      weather_mode,
      selection$effective_cooldown,
      outfit$top_item_name[[1]],
      outfit$top_img_url[[1]],
      outfit$bottom_item_name[[1]],
      outfit$bottom_img_url[[1]],
      outfit$shoes_item_name[[1]],
      outfit$shoes_img_url[[1]]
    )
  )
}

choose_active_recommendation <- function(
  connection,
  starting_state_version,
  starting_active_recommendation_id = NULL,
  choose_index = sample.int,
  config = clothes_app_config
) {
  if (
    length(starting_state_version) != 1L
    || is.na(starting_state_version)
    || starting_state_version < 0
    || starting_state_version != as.integer(starting_state_version)
  ) {
    stop("Starting state version must be one nonnegative integer.", call. = FALSE)
  }

  result <- DBI::dbWithTransaction(connection, {
    state <- read_recommendation_state(connection, config)
    current_active_id <- state$settings$active_recommendation_id[[1]]
    current_version <- state$settings$state_version[[1]]
    state_matches <- (
      current_version == starting_state_version
      && same_active_recommendation(
        current_active_id,
        starting_active_recommendation_id
      )
    )

    if (!state_matches || !is.na(current_active_id)) {
      list(state = state, created = FALSE, stale = !state_matches)
    } else {
      weather_mode <- state$settings$weather_mode[[1]]
      eligible_outfits <- read_eligible_catalog_outfits(
        connection,
        weather_mode,
        config
      )
      worn_top_ids <- read_recent_worn_top_ids(connection, config = config)
      selection <- select_recommended_outfit(
        eligible_outfits,
        worn_top_ids = worn_top_ids,
        choose_index = choose_index
      )
      recommendation_id <- db_new_uuid(connection)
      selection_cycle_id <- db_new_uuid(connection)

      insert_active_recommendation(
        connection,
        selection,
        recommendation_id,
        selection_cycle_id,
        weather_mode,
        config
      )

      updated_rows <- DBI::dbExecute(
        connection,
        sprintf(
          paste(
            "UPDATE %s",
            "SET active_recommendation_id = ?,",
            "state_version = state_version + 1,",
            "updated_at = current_timestamp",
            "WHERE settings_id = ?",
            "AND active_recommendation_id IS NULL",
            "AND state_version = ?"
          ),
          db_table_name(connection, "app_settings", config)
        ),
        params = list(
          recommendation_id,
          config$settings_id,
          as.integer(starting_state_version)
        )
      )

      if (updated_rows != 1L) {
        stop(
          "Application state changed while choosing a recommendation.",
          call. = FALSE
        )
      }

      list(
        state = read_recommendation_state(connection, config),
        created = TRUE,
        stale = FALSE
      )
    }
  })

  invisible(result)
}
