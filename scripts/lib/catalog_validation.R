catalog_source_columns <- function() {
  c(
    "item_id",
    "item_name",
    "category",
    "color",
    "season",
    "img_url",
    "active"
  )
}

new_catalog_issue <- function(
  severity,
  sheet_row,
  column,
  value,
  message
) {
  tibble::tibble(
    severity = severity,
    sheet_row = as.integer(sheet_row),
    column = column,
    value = as.character(value),
    message = message
  )
}

catalog_column_issues <- function(catalog) {
  required_columns <- catalog_source_columns()
  missing_columns <- setdiff(required_columns, names(catalog))
  extra_columns <- setdiff(names(catalog), required_columns)

  dplyr::bind_rows(
    purrr::map_dfr(
      missing_columns,
      ~ new_catalog_issue(
        "error",
        NA_integer_,
        .x,
        NA_character_,
        "Required column is missing."
      )
    ),
    purrr::map_dfr(
      extra_columns,
      ~ new_catalog_issue(
        "error",
        NA_integer_,
        .x,
        NA_character_,
        "Unexpected column is present."
      )
    )
  )
}

catalog_row_issues <- function(
  catalog,
  invalid,
  column,
  message,
  severity = "error"
) {
  invalid[is.na(invalid)] <- FALSE
  invalid_rows <- which(invalid)

  if (length(invalid_rows) == 0L) {
    return(new_catalog_issue(
      character(),
      integer(),
      character(),
      character(),
      character()
    ))
  }

  new_catalog_issue(
    severity = severity,
    sheet_row = catalog$.sheet_row[invalid_rows],
    column = column,
    value = catalog[[column]][invalid_rows],
    message = message
  )
}

prepare_catalog_text <- function(catalog) {
  catalog |>
    dplyr::mutate(
      dplyr::across(
        dplyr::all_of(catalog_source_columns()),
        ~ stringr::str_trim(as.character(.x))
      ),
      .sheet_row = dplyr::row_number() + 1L,
      .before = 1L
    )
}

catalog_value_issues <- function(catalog) {
  blank <- function(value) is.na(value) | value == ""
  active_text <- stringr::str_to_upper(catalog$active)
  google_image_host <- stringr::str_detect(
    catalog$img_url,
    paste0(
      "^https://(?:drive\\.google\\.com|",
      "drive\\.usercontent\\.google\\.com|",
      "lh3\\.googleusercontent\\.com)"
    )
  )
  browser_safe_google_image <- stringr::str_detect(
    catalog$img_url,
    paste0(
      "^https://lh3\\.googleusercontent\\.com/d/",
      "[A-Za-z0-9_-]+=w1200$"
    )
  )

  duplicated_id <- (
    duplicated(catalog$item_id)
    | duplicated(catalog$item_id, fromLast = TRUE)
  ) & !blank(catalog$item_id)

  issues <- dplyr::bind_rows(
    purrr::map_dfr(
      catalog_source_columns(),
      ~ catalog_row_issues(
        catalog,
        blank(catalog[[.x]]),
        .x,
        "Value is required."
      )
    ),
    catalog_row_issues(
      catalog,
      !blank(catalog$item_id) & !stringr::str_detect(
        catalog$item_id,
        "^[a-z0-9]+(?:_[a-z0-9]+)*$"
      ),
      "item_id",
      "Use a lowercase underscore-separated slug."
    ),
    catalog_row_issues(
      catalog,
      duplicated_id,
      "item_id",
      "Item ID is duplicated."
    ),
    catalog_row_issues(
      catalog,
      !blank(catalog$category) & !catalog$category %in% c(
        "top",
        "bottom",
        "shoes"
      ),
      "category",
      "Category must be top, bottom, or shoes."
    ),
    catalog_row_issues(
      catalog,
      !blank(catalog$color) & !stringr::str_detect(
        catalog$color,
        "^[a-z0-9]+(?:_[a-z0-9]+)*$"
      ),
      "color",
      "Color must be a lowercase compatibility slug."
    ),
    catalog_row_issues(
      catalog,
      !blank(catalog$season) & !catalog$season %in% c(
        "all",
        "warm",
        "cold"
      ),
      "season",
      "Season must be all, warm, or cold."
    ),
    catalog_row_issues(
      catalog,
      !blank(catalog$img_url) & !stringr::str_detect(
        catalog$img_url,
        "^https://"
      ),
      "img_url",
      "Image URL must begin with https://."
    ),
    catalog_row_issues(
      catalog,
      !blank(catalog$img_url)
        & google_image_host
        & !browser_safe_google_image,
      "img_url",
      paste(
        "Use a browser-safe Google image URL in the form",
        "https://lh3.googleusercontent.com/d/FILE_ID=w1200."
      )
    ),
    catalog_row_issues(
      catalog,
      !blank(catalog$active) & !active_text %in% c("TRUE", "FALSE"),
      "active",
      "Active must be TRUE or FALSE."
    )
  )

  active_categories <- catalog |>
    dplyr::filter(active_text == "TRUE") |>
    dplyr::pull(category) |>
    unique()
  missing_active_categories <- setdiff(
    c("top", "bottom", "shoes"),
    active_categories
  )

  dplyr::bind_rows(
    issues,
    purrr::map_dfr(
      missing_active_categories,
      ~ new_catalog_issue(
        "error",
        NA_integer_,
        "category",
        .x,
        paste("No active", .x, "item is available.")
      )
    )
  )
}

normalize_catalog <- function(catalog) {
  catalog |>
    dplyr::transmute(
      item_id,
      item_name,
      category,
      color,
      season,
      img_url,
      active = stringr::str_to_upper(active) == "TRUE"
    )
}

validate_catalog <- function(catalog) {
  column_issues <- catalog_column_issues(catalog)

  if (nrow(column_issues) > 0L) {
    return(list(data = NULL, issues = column_issues))
  }

  prepared_catalog <- prepare_catalog_text(catalog)
  value_issues <- catalog_value_issues(prepared_catalog)

  list(
    data = if (nrow(value_issues) == 0L) {
      normalize_catalog(prepared_catalog)
    } else {
      NULL
    },
    issues = value_issues
  )
}

catalog_has_errors <- function(validation) {
  any(validation$issues$severity == "error")
}
