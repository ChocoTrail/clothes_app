# Operations

## Initialize and verify locally

From the project root:

```sh
rv sync --locked
Rscript scripts/initialize_database.R --local
Rscript tests/testthat.R
```

Local initialization creates or reuses `output/clothes_app_local.duckdb`. The
`output/` directory is ignored by Git, so the local database and its data are
never committed. Re-running the initializer preserves existing settings,
catalog rows, and recommendation history. It does not connect to or change
MotherDuck.

The running app also defaults to the local database. The non-secret
`CLOTHES_APP_DATABASE_TARGET` setting accepts `local` or `motherduck`; leaving
it unset is equivalent to `local`. A later deployment will set it to
`motherduck` alongside the required MotherDuck token.

## Preview and publish the catalog locally

From an interactive R console in the project root:

```r
source("scripts/publish_catalog.R")

publish_catalog(target = "local")
publish_catalog(target = "local", write = TRUE)
```

The first call validates the Google Sheet, generates outfits, and compares them
with the local DuckDB catalog without writing. Review its counts before running
the second call. The write call stages both catalog tables and commits them in
one transaction. It never modifies `app_settings` or `recommendations`.

MotherDuck uses the same preview-first workflow:

```r
publish_catalog(target = "motherduck")
publish_catalog(target = "motherduck", write = TRUE)
```

Review the dry-run counts before the write call. MotherDuck publication uses
the same staging tables, existing-catalog checks, and transaction as local
publication; it does not modify `app_settings` or `recommendations`.

## Initialize MotherDuck

1. Set `MOTHERDUCK_TOKEN` in the local environment. Never add the value to a tracked file.
2. Run `Rscript scripts/initialize_database.R` from the project root.
3. Confirm the output lists `clothing_items`, `outfits`, `recommendations`, `app_settings`, and `wear_history`, with the singleton setting in warm mode.

The R connection performs the required sequence explicitly:

1. Open an embedded DuckDB connection.
2. Install the `motherduck` extension when necessary.
3. Load the extension.
4. Attach `md:choco_trail` as `choco_trail`.
5. Select that database.
6. Apply `db/schema.sql` as one transactional batch.
7. Disconnect even if initialization fails.

The initializer is repeatable. Existing settings and recommendation history are preserved.

## Secret handling

`MOTHERDUCK_TOKEN` is the only required secret. The connection temporarily exposes it under the extension's expected lowercase environment name only while attaching MotherDuck, then restores the prior process environment. The token is never written to SQL, application messages, logs, or committed files.

`CLOTHES_APP_DATABASE_TARGET` is configuration, not a secret. Use `local` for
development and `motherduck` only in an environment that has a valid
`MOTHERDUCK_TOKEN`.
