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
it unset is equivalent to `local`. The production Connect Cloud deployment sets
it to `motherduck` alongside the required MotherDuck token.

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

## Generate the deployment manifest

From the project root, run:

```sh
Rscript scripts/write_manifest.R
```

The generator resolves dependencies from the active project library and writes
`manifest.json` from an explicit runtime file list. The deployment bundle
contains `app.R`, the sourced files under `R/`, and the required files under
`www/`. It excludes local databases, credentials, tests, catalog-publishing
tools, source images, and environment-management files.

Regenerate and commit `manifest.json` whenever a runtime file or runtime package
dependency changes.

## Deploy through Posit Connect Cloud

The production content is configured with:

- GitHub repository: `ChocoTrail/clothes_app`
- Branch: `main`
- Framework: Shiny
- Primary file: `app.R`
- Automatic publish on push: enabled
- Default Connect Cloud runtime and worker settings

The content has two Connect Cloud variables:

- `MOTHERDUCK_TOKEN`: secret MotherDuck credential
- `CLOTHES_APP_DATABASE_TARGET`: `motherduck`

Never put the token in GitHub, `manifest.json`, or application code. The Google
Sheet OAuth credential is also local-only and is not required by the deployed
app.

For an ordinary code change:

1. Test the change locally with `Rscript tests/testthat.R` and a manual app run.
2. Run `Rscript scripts/write_manifest.R` if runtime code, runtime assets, or
   package dependencies changed.
3. Review `git status` and `git diff`.
4. Commit and push to `main`.
5. Watch the Connect Cloud build logs until the new commit is active.

The deployment should then be checked in its standalone public view. Confirm
the ready-state card, weather persistence, recommendation persistence after a
refresh, rerolling, worn confirmation, history accordions, images, and the
mobile layout. Avoid creating unnecessary production history while performing
routine visual-only checks.

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

## Troubleshooting and recovery

- **The deployed app shows local or empty state:** confirm
  `CLOTHES_APP_DATABASE_TARGET=motherduck` in the content variables, then
  republish.
- **MotherDuck connection fails:** confirm the `MOTHERDUCK_TOKEN` variable is
  present and current. Do not include its value when sharing logs.
- **A Connect Cloud package build fails:** regenerate `manifest.json` from the
  locked local `rv` environment, commit it, and push again.
- **A catalog change is missing:** run the MotherDuck publication preview,
  inspect its counts, and only then run the write publication.
- **A deployment fails:** the failed build does not require a database reset.
  Fix the reported issue locally, rerun the tests, and push a new commit. Use
  the Connect Cloud logs and deployed commit SHA to confirm which version is
  active.
- **Local data appears wrong:** first confirm the selected database target.
  Re-running the schema initializer is safe and does not clear history. The
  ignored local DuckDB file should only be removed when an intentional full
  local reset is desired.
