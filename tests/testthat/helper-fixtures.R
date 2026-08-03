project_root <- normalizePath(
  file.path(testthat::test_path(), "..", ".."),
  mustWork = TRUE
)

source(file.path(project_root, "R", "config.R"))
source(file.path(project_root, "R", "database.R"))
source(
  file.path(project_root, "scripts", "lib", "catalog_validation.R")
)
source(file.path(project_root, "scripts", "lib", "compatibility.R"))
source(file.path(project_root, "scripts", "lib", "catalog_io.R"))

new_test_database <- function() {
  connection <- db_connect_local()
  initialize_database_schema(
    connection,
    file.path(project_root, "db", "schema.sql")
  )
  connection
}

seed_test_catalog <- function(connection) {
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO clothes_app.clothing_items",
      "(item_id, item_name, category, color, season, img_url, active, catalog_publication_id)",
      "VALUES",
      "('top_one', 'Top One', 'top', 'black', 'all', 'https://example.com/top.png', TRUE, 'publication-one'),",
      "('bottom_one', 'Bottom One', 'bottom', 'gray', 'all', 'https://example.com/bottom.png', TRUE, 'publication-one'),",
      "('shoes_one', 'Shoes One', 'shoes', 'black', 'all', 'https://example.com/shoes.png', TRUE, 'publication-one')"
    )
  )

  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO clothes_app.outfits",
      "(outfit_id, top_item_id, bottom_item_id, shoes_item_id, is_compatible, exclusion_reason, catalog_publication_id)",
      "VALUES",
      "('top_one--bottom_one--shoes_one', 'top_one', 'bottom_one', 'shoes_one', TRUE, NULL, 'publication-one')"
    )
  )

  invisible(connection)
}

compatibility_catalog_fixture <- function() {
  tibble::tribble(
    ~item_id, ~item_name, ~category, ~color, ~season, ~img_url, ~active,
    "top_black", "Black Top", "top", "black", "all", "https://example.com/top-black.png", TRUE,
    "top_white", "White Top", "top", "white", "all", "https://example.com/top-white.png", TRUE,
    "bottom_darkblue", "Dark Blue Bottom", "bottom", "darkblue", "all", "https://example.com/bottom-darkblue.png", TRUE,
    "bottom_khaki", "Khaki Bottom", "bottom", "khaki", "all", "https://example.com/bottom-khaki.png", TRUE,
    "shoes_gray", "Gray Shoes", "shoes", "gray", "all", "https://example.com/shoes-gray.png", TRUE,
    "shoes_black", "Black Shoes", "shoes", "black", "all", "https://example.com/shoes-black.png", TRUE
  )
}
