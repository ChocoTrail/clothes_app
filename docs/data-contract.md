# Data contract

## Google Sheet source

The private `clothing_items` spreadsheet uses the `data` tab and exactly these source columns:

| Field | Type | Rules |
|---|---|---|
| `item_id` | text | Permanent, unique lowercase underscore-separated slug; never reused. |
| `item_name` | text | Nonempty display name. |
| `category` | text | `top`, `bottom`, or `shoes`. |
| `color` | text | Lowercase compatibility value such as `black`, `darkblue`, `gray`, `khaki`, or `silver`. |
| `season` | text | `all`, `warm`, or `cold`. |
| `img_url` | text | Public browser-safe Google image URL in the form `https://lh3.googleusercontent.com/d/FILE_ID=w1200`. |
| `active` | logical | Long-term recommendation inclusion toggle. |

## MotherDuck objects

All objects live in `choco_trail.clothes_app`.

### `clothing_items`

Preserves the seven source fields and adds `catalog_publication_id` and `published_at`.

### `outfits`

Stores the deterministic `outfit_id`, top/bottom/shoes item IDs, compatibility flag, optional exclusion reason, and publication metadata. The three item IDs are unique as a group.

### `recommendations`

Stores each displayed recommendation, including its cycle, outfit, publication,
weather mode, effective cooldown, lifecycle status, creation timestamp,
nullable `worn_on` date, and the displayed item-name and image-URL snapshots.

Allowed statuses are `active`, `rerolled`, `worn`, and `season_invalidated`.
`worn_on` is required when status is `worn` and is absent for every other
status. It records the user-selected date the outfit was worn. The app does not
store a separate timestamp for when that confirmation was entered. The selected
date cannot be in the future when it is saved.

### `app_settings`

Contains exactly one row with `settings_id = 'singleton'`. It stores the persistent weather mode, optional active recommendation pointer, state version, and update timestamp. Initial values are warm mode, no active recommendation, and state version zero.

### `wear_history`

A read-only view of recommendations whose status is `worn`. It exposes
`worn_on` plus the snapshotted names and image URLs. Results are ordered by the
actual wear date, with recommendation ID as the deterministic tie-breaker.

During the schema update, existing worn recommendations derive `worn_on` from
their former `resolved_at` values in Pacific time. The old resolution timestamp
is then removed rather than retained as a saved-at field.
