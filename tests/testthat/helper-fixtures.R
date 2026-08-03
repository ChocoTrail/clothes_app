project_root <- normalizePath(
  file.path(testthat::test_path(), "..", ".."),
  mustWork = TRUE
)

source(file.path(project_root, "R", "config.R"))
source(file.path(project_root, "R", "database.R"))

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
      "('top-one', 'Top One', 'top', 'black', 'all', 'https://example.com/top.png', TRUE, 'publication-one'),",
      "('pants-one', 'Pants One', 'pants', 'grey', 'all', 'https://example.com/pants.png', TRUE, 'publication-one'),",
      "('shoes-one', 'Shoes One', 'shoes', 'black', 'all', 'https://example.com/shoes.png', TRUE, 'publication-one')"
    )
  )

  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO clothes_app.outfits",
      "(outfit_id, top_item_id, pants_item_id, shoes_item_id, is_compatible, exclusion_reason, catalog_publication_id)",
      "VALUES",
      "('top-one--pants-one--shoes-one', 'top-one', 'pants-one', 'shoes-one', TRUE, NULL, 'publication-one')"
    )
  )

  invisible(connection)
}
