CREATE SCHEMA IF NOT EXISTS clothes_app;
SET schema = 'clothes_app';

CREATE TABLE IF NOT EXISTS clothing_items (
  item_id VARCHAR PRIMARY KEY,
  item_name VARCHAR NOT NULL,
  category VARCHAR NOT NULL,
  color VARCHAR NOT NULL,
  season VARCHAR NOT NULL,
  img_url VARCHAR NOT NULL,
  active BOOLEAN NOT NULL,
  catalog_publication_id VARCHAR NOT NULL,
  published_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT current_timestamp,
  CONSTRAINT clothing_items_item_id_slug
    CHECK (regexp_full_match(item_id, '[a-z0-9]+(?:-[a-z0-9]+)*')),
  CONSTRAINT clothing_items_name_present
    CHECK (length(trim(item_name)) > 0),
  CONSTRAINT clothing_items_category_valid
    CHECK (category IN ('top', 'pants', 'shoes')),
  CONSTRAINT clothing_items_color_slug
    CHECK (regexp_full_match(color, '[a-z0-9]+(?:_[a-z0-9]+)*')),
  CONSTRAINT clothing_items_season_valid
    CHECK (season IN ('all', 'warm', 'cold')),
  CONSTRAINT clothing_items_img_url_https
    CHECK (starts_with(img_url, 'https://')),
  CONSTRAINT clothing_items_publication_present
    CHECK (length(trim(catalog_publication_id)) > 0)
);

CREATE TABLE IF NOT EXISTS outfits (
  outfit_id VARCHAR PRIMARY KEY,
  top_item_id VARCHAR NOT NULL REFERENCES clothing_items (item_id),
  pants_item_id VARCHAR NOT NULL REFERENCES clothing_items (item_id),
  shoes_item_id VARCHAR NOT NULL REFERENCES clothing_items (item_id),
  is_compatible BOOLEAN NOT NULL,
  exclusion_reason VARCHAR,
  catalog_publication_id VARCHAR NOT NULL,
  published_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT current_timestamp,
  CONSTRAINT outfits_items_unique
    UNIQUE (top_item_id, pants_item_id, shoes_item_id),
  CONSTRAINT outfits_compatibility_reason_consistent
    CHECK (
      (is_compatible AND exclusion_reason IS NULL)
      OR
      (
        NOT is_compatible
        AND exclusion_reason IS NOT NULL
        AND length(trim(exclusion_reason)) > 0
      )
    ),
  CONSTRAINT outfits_publication_present
    CHECK (length(trim(catalog_publication_id)) > 0)
);

CREATE TABLE IF NOT EXISTS recommendations (
  recommendation_id VARCHAR PRIMARY KEY,
  selection_cycle_id VARCHAR NOT NULL,
  outfit_id VARCHAR NOT NULL REFERENCES outfits (outfit_id),
  catalog_publication_id VARCHAR NOT NULL,
  weather_mode VARCHAR NOT NULL,
  effective_cooldown SMALLINT NOT NULL,
  status VARCHAR NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT current_timestamp,
  resolved_at TIMESTAMP WITH TIME ZONE,
  top_item_name VARCHAR NOT NULL,
  top_img_url VARCHAR NOT NULL,
  pants_item_name VARCHAR NOT NULL,
  pants_img_url VARCHAR NOT NULL,
  shoes_item_name VARCHAR NOT NULL,
  shoes_img_url VARCHAR NOT NULL,
  CONSTRAINT recommendations_cycle_present
    CHECK (length(trim(selection_cycle_id)) > 0),
  CONSTRAINT recommendations_publication_present
    CHECK (length(trim(catalog_publication_id)) > 0),
  CONSTRAINT recommendations_weather_valid
    CHECK (weather_mode IN ('warm', 'cold')),
  CONSTRAINT recommendations_cooldown_valid
    CHECK (effective_cooldown BETWEEN 0 AND 5),
  CONSTRAINT recommendations_status_valid
    CHECK (
      status IN ('active', 'rerolled', 'worn', 'season_invalidated')
    ),
  CONSTRAINT recommendations_resolution_consistent
    CHECK (
      (status = 'active' AND resolved_at IS NULL)
      OR
      (status <> 'active' AND resolved_at IS NOT NULL)
    ),
  CONSTRAINT recommendations_image_urls_https
    CHECK (
      starts_with(top_img_url, 'https://')
      AND starts_with(pants_img_url, 'https://')
      AND starts_with(shoes_img_url, 'https://')
    )
);

CREATE TABLE IF NOT EXISTS app_settings (
  settings_id VARCHAR PRIMARY KEY,
  weather_mode VARCHAR NOT NULL DEFAULT 'warm',
  active_recommendation_id VARCHAR REFERENCES recommendations (recommendation_id),
  state_version BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT current_timestamp,
  CONSTRAINT app_settings_singleton
    CHECK (settings_id = 'singleton'),
  CONSTRAINT app_settings_weather_valid
    CHECK (weather_mode IN ('warm', 'cold')),
  CONSTRAINT app_settings_state_version_valid
    CHECK (state_version >= 0)
);

INSERT INTO app_settings (
  settings_id,
  weather_mode,
  active_recommendation_id,
  state_version
)
VALUES ('singleton', 'warm', NULL, 0)
ON CONFLICT (settings_id) DO NOTHING;

CREATE OR REPLACE VIEW wear_history AS
SELECT
  recommendation_id,
  selection_cycle_id,
  outfit_id,
  catalog_publication_id,
  weather_mode,
  effective_cooldown,
  created_at AS recommended_at,
  resolved_at AS worn_at,
  top_item_name,
  top_img_url,
  pants_item_name,
  pants_img_url,
  shoes_item_name,
  shoes_img_url
FROM recommendations
WHERE status = 'worn';
