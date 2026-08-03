# Data contract

## Google Sheet source

The private `clothing_items` spreadsheet uses the `data` tab and exactly these source columns:

| Field | Type | Rules |
|---|---|---|
| `item_id` | text | Permanent, unique lowercase slug; never reused. |
| `item_name` | text | Nonempty display name. |
| `category` | text | `top`, `bottom`, or `shoes`. |
| `color` | text | Lowercase compatibility value such as `black`, `dark_blue`, `grey`, or `khaki`. |
| `season` | text | `all`, `warm`, or `cold`. |
| `img_url` | text | Public direct HTTPS image URL. |
| `active` | logical | Long-term recommendation inclusion toggle. |

## MotherDuck objects

All objects live in `choco_trail.clothes_app`.

### `clothing_items`

Preserves the seven source fields and adds `catalog_publication_id` and `published_at`.

### `outfits`

Stores the deterministic `outfit_id`, top/bottom/shoes item IDs, compatibility flag, optional exclusion reason, and publication metadata. The three item IDs are unique as a group.

### `recommendations`

Stores each displayed recommendation, including its cycle, outfit, publication, weather mode, effective cooldown, lifecycle status, timestamps, and the displayed item-name and image-URL snapshots.

Allowed statuses are `active`, `rerolled`, `worn`, and `season_invalidated`. Active rows have no resolution timestamp; every resolved status does.

### `app_settings`

Contains exactly one row with `settings_id = 'singleton'`. It stores the persistent weather mode, optional active recommendation pointer, state version, and update timestamp. Initial values are warm mode, no active recommendation, and state version zero.

### `wear_history`

A read-only view of recommendations whose status is `worn`. It exposes the snapshotted names and image URLs and uses `resolved_at` as `worn_at`.
