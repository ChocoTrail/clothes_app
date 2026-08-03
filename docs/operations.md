# Operations

## Initialize and verify locally

From the project root:

```sh
rv sync --locked
Rscript scripts/initialize_database.R --local
Rscript tests/testthat.R
```

Local initialization uses an isolated, in-memory DuckDB database. It validates the production schema without creating a local database file, using the shared DuckDB home, or changing MotherDuck.

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
