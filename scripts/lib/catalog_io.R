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
