outfits_at_cooldown <- function(
  eligible_outfits,
  worn_top_ids,
  cooldown
) {
  recent_top_ids <- utils::head(worn_top_ids, cooldown)

  eligible_outfits |>
    dplyr::filter(!.data$top_item_id %in% recent_top_ids)
}

resolve_effective_cooldown <- function(
  eligible_outfits,
  worn_top_ids,
  maximum_cooldown = 5L
) {
  if (nrow(eligible_outfits) == 0L) {
    stop(
      "No compatible, active outfits are eligible for this weather mode.",
      call. = FALSE
    )
  }

  for (cooldown in seq.int(maximum_cooldown, 0L)) {
    candidates <- outfits_at_cooldown(
      eligible_outfits,
      worn_top_ids,
      cooldown
    )

    if (nrow(candidates) > 0L) {
      return(as.integer(cooldown))
    }
  }

  stop("No outfit is available even at a zero cooldown.", call. = FALSE)
}

validate_effective_cooldown <- function(effective_cooldown) {
  if (
    length(effective_cooldown) != 1L
    || is.na(effective_cooldown)
    || effective_cooldown != as.integer(effective_cooldown)
    || !effective_cooldown %in% 0:5
  ) {
    stop("Effective cooldown must be one whole number from 0 to 5.", call. = FALSE)
  }

  as.integer(effective_cooldown)
}

choose_random_value <- function(values, choose_index = sample.int) {
  chosen_index <- choose_index(length(values), 1L)

  if (
    length(chosen_index) != 1L
    || is.na(chosen_index)
    || chosen_index != as.integer(chosen_index)
    || chosen_index < 1L
    || chosen_index > length(values)
  ) {
    stop("Random index chooser returned an invalid index.", call. = FALSE)
  }

  values[[as.integer(chosen_index)]]
}

select_recommended_outfit <- function(
  eligible_outfits,
  worn_top_ids = character(),
  shown_outfit_ids = character(),
  effective_cooldown = NULL,
  choose_index = sample.int
) {
  if (is.null(effective_cooldown)) {
    effective_cooldown <- resolve_effective_cooldown(
      eligible_outfits,
      worn_top_ids
    )
  } else {
    effective_cooldown <- validate_effective_cooldown(effective_cooldown)
  }

  cooldown_candidates <- outfits_at_cooldown(
    eligible_outfits,
    worn_top_ids,
    effective_cooldown
  )

  if (nrow(cooldown_candidates) == 0L) {
    stop(
      "No outfit is available at the selection cycle's fixed cooldown.",
      call. = FALSE
    )
  }

  unseen_candidates <- cooldown_candidates |>
    dplyr::filter(!.data$outfit_id %in% shown_outfit_ids)
  using_unseen_candidates <- nrow(unseen_candidates) > 0L
  selection_pool <- if (using_unseen_candidates) {
    unseen_candidates
  } else {
    cooldown_candidates
  }

  eligible_top_ids <- unique(selection_pool$top_item_id)
  selected_top_id <- choose_random_value(eligible_top_ids, choose_index)
  selected_top_outfits <- selection_pool |>
    dplyr::filter(.data$top_item_id == selected_top_id)
  selected_outfit_id <- choose_random_value(
    selected_top_outfits$outfit_id,
    choose_index
  )
  selected_outfit <- selected_top_outfits |>
    dplyr::filter(.data$outfit_id == selected_outfit_id) |>
    dplyr::slice_head(n = 1L)

  list(
    outfit = selected_outfit,
    effective_cooldown = effective_cooldown,
    used_unseen_pool = using_unseen_candidates
  )
}
