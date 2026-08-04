# Clothes App

A mobile-first R Shiny app that recommends one compatible work outfit from a
personal wardrobe. It remembers the current weather mode, keeps one active
recommendation stable across sessions, supports rerolls, and records confirmed
outfits in a collapsible wear history.

The production app runs on Posit Connect Cloud, reads and writes persistent
state in MotherDuck, and republishes automatically from the `main` branch of
[`ChocoTrail/clothes_app`](https://github.com/ChocoTrail/clothes_app).

## How it works

There are three distinct pieces:

1. The private Google Sheet is the editable clothing catalog.
2. `scripts/publish_catalog.R` validates the Sheet, generates every
   top-bottom-shoes combination, applies the compatibility rules, and publishes
   the catalog to either local DuckDB or MotherDuck.
3. The Shiny app reads the published catalog and stores weather settings and
   recommendation history in the selected database.

The app never edits the Google Sheet. Publishing a catalog never replaces app
settings or recommendation history.

### Recommendation behavior

- Every visit starts on **Ready when you are**. **Choose my outfit** creates a
  recommendation or reveals the already-active one.
- Only compatible outfits with three active, weather-eligible items can be
  selected.
- The algorithm excludes tops from the last five confirmed outfits. If that
  leaves no candidates, it relaxes the cooldown one step at a time.
- It chooses an eligible top first and then a bottom-shoes combination, so tops
  with more combinations do not receive an unfair advantage.
- **Give me another** avoids exact combinations already shown in the current
  cycle while unseen choices remain. Rerolled outfits do not affect recency.
- **I wore this** completes the cycle, clears the active recommendation, and
  adds the snapshotted names and images to wear history.
- Changing between Warm and Cold clears any active recommendation and keeps the
  new weather mode for later sessions.

## Local setup

### Prerequisites

- R 4.6.1
- [`rv`](https://a2-ai.github.io/rv-docs/intro/installation/)
- A MotherDuck token only when connecting to MotherDuck
- Google authorization only when reading the private catalog Sheet

From the project root, restore the locked R environment:

```sh
rv sync --locked
```

Initialize or safely reuse the local DuckDB database:

```sh
Rscript scripts/initialize_database.R --local
```

This creates `output/clothes_app_local.duckdb`. The `output/` directory is
ignored by Git. Re-running the initializer preserves existing local data.

### Populate the local catalog

In an interactive R console in the project root:

```r
source("scripts/publish_catalog.R")

publish_catalog(target = "local")
publish_catalog(target = "local", write = TRUE)
```

Always review the dry-run counts from the first call before allowing the second
call to write.

### Run the app locally

The app defaults to the local database when
`CLOTHES_APP_DATABASE_TARGET` is unset:

```r
shiny::runApp()
```

Local recommendations and wear history remain in the ignored DuckDB file
between sessions.

## Secrets and database targets

Copy `.Renviron.example` to `.Renviron` and add the MotherDuck token when
MotherDuck access is needed:

```text
MOTHERDUCK_TOKEN=your_token_here
```

Do not add quotes, and never commit `.Renviron` or paste the token into logs,
issues, or documentation.

`CLOTHES_APP_DATABASE_TARGET` controls the running app:

- unset or `local`: use `output/clothes_app_local.duckdb`
- `motherduck`: use `choco_trail.clothes_app` and require
  `MOTHERDUCK_TOKEN`

Production defines both variables in Posit Connect Cloud. Google credentials
are not deployed because catalog publication runs manually from a local R
session.

## Change the wardrobe

Edit the `data` tab of the `clothing_items` Google Sheet. The exact columns and
allowed values are documented in [`docs/data-contract.md`](docs/data-contract.md).

Important rules:

- Keep `item_id` permanent, unique, lowercase, and underscore-separated.
- Use `top`, `bottom`, or `shoes` for `category`.
- Use consistent lowercase colors such as `gray` and `darkblue`.
- Use browser-safe image URLs in the form
  `https://lh3.googleusercontent.com/d/FILE_ID=w1200`.
- Set an item to inactive instead of deleting its row.

Preview and then publish to MotherDuck from an interactive R console:

```r
source("scripts/publish_catalog.R")

publish_catalog(target = "motherduck")
publish_catalog(target = "motherduck", write = TRUE)
```

The production app sees the new catalog without a code deployment.

## Change app behavior or appearance

The main implementation locations are:

- Compatibility rules: `scripts/lib/compatibility.R`
- Catalog validation: `scripts/lib/catalog_validation.R`
- Recommendation algorithm: `R/recommendation.R`
- Persistent state transitions: `R/recommendation_state.R`
- Shiny behavior: `R/app_server.R`
- UI components and layout: `R/ui_components.R` and `R/app_ui.R`
- Styling: `www/styles.css`
- Database objects: `db/schema.sql`
- Non-secret constants: `R/config.R`

Update the matching tests whenever behavior changes. After making changes, run:

```sh
Rscript tests/testthat.R
```

If a runtime file or package dependency changed, regenerate the deployment
manifest:

```sh
Rscript scripts/write_manifest.R
```

Review `git status` and the diff before committing. A push to `main` triggers
an automatic Connect Cloud republish:

```sh
git add .
git commit -m "Describe the change"
git push
```

## Documentation

- [`DESIGN.md`](DESIGN.md): product behavior, architecture, data model, and
  design decisions
- [`docs/data-contract.md`](docs/data-contract.md): Google Sheet and database
  fields
- [`docs/operations.md`](docs/operations.md): initialization, publication,
  deployment, verification, and troubleshooting
