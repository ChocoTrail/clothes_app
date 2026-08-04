weather_mode_control <- function(weather_mode, busy = FALSE) {
  weather_button <- function(value) {
    active <- identical(weather_mode, value)

    shiny::tags$button(
      id = paste0("weather_", value),
      type = "button",
      class = paste(
        c(
          "btn",
          "action-button",
          "weather-mode__option",
          if (active) "is-active"
        ),
        collapse = " "
      ),
      `aria-pressed` = if (active) "true" else "false",
      disabled = if (busy) "disabled" else NULL,
      shiny::span(
        class = "action-label",
        stringr::str_to_sentence(value)
      )
    )
  }

  shiny::div(
    class = "weather-mode",
    shiny::span(class = "weather-mode__label", "Weather mode"),
    shiny::div(
      class = "weather-mode__options",
      role = "group",
      `aria-label` = "Weather mode",
      weather_button("warm"),
      weather_button("cold")
    )
  )
}

outfit_item_card <- function(role, item_name, image_url) {
  bslib::card(
    class = "outfit-card",
    shiny::div(
      class = "outfit-card__image-field",
      shiny::tags$img(
        class = "outfit-card__image",
        src = image_url,
        alt = paste(role, item_name, sep = ": "),
        loading = "lazy"
      )
    ),
    shiny::div(
      class = "outfit-card__content",
      shiny::p(class = "outfit-card__role", role),
      shiny::h3(class = "outfit-card__name", item_name)
    )
  )
}

empty_decision_panel <- function(weather_mode, busy = FALSE) {
  shiny::tags$section(
    class = "decision-panel decision-panel--empty",
    shiny::h2("Ready when you are"),
    shiny::p(
      "Choose one compatible ",
      weather_mode,
      "-weather outfit from your current wardrobe."
    ),
    shiny::actionButton(
      "choose_outfit",
      "Choose my outfit",
      class = "btn-primary decision-panel__primary-action",
      disabled = if (busy) "disabled" else NULL
    )
  )
}

active_decision_panel <- function(recommendation, busy = FALSE) {
  cooldown <- recommendation$effective_cooldown[[1]]

  shiny::tags$section(
    class = "decision-panel",
    shiny::div(
      class = "decision-panel__heading",
      shiny::div(
        shiny::p(class = "eyebrow", "Today’s recommendation"),
        shiny::h2("Your outfit")
      ),
      shiny::span(
        class = "decision-panel__metadata",
        paste0("cooldown ", cooldown)
      )
    ),
    shiny::div(
      class = "outfit-grid",
      outfit_item_card(
        "Top",
        recommendation$top_item_name[[1]],
        recommendation$top_img_url[[1]]
      ),
      outfit_item_card(
        "Bottom",
        recommendation$bottom_item_name[[1]],
        recommendation$bottom_img_url[[1]]
      ),
      outfit_item_card(
        "Shoes",
        recommendation$shoes_item_name[[1]],
        recommendation$shoes_img_url[[1]]
      )
    ),
    shiny::div(
      class = "decision-panel__actions",
      shiny::actionButton(
        "confirm_outfit",
        "I wore this",
        class = "btn-primary decision-panel__primary-action",
        disabled = if (busy) "disabled" else NULL
      ),
      shiny::actionButton(
        "reroll_outfit",
        "Give me another",
        class = "btn-outline-secondary decision-panel__secondary-action",
        disabled = if (busy) "disabled" else NULL
      )
    )
  )
}

wear_history_item <- function(role, item_name, image_url) {
  shiny::div(
    class = "history-item",
    shiny::div(
      class = "history-item__image-field",
      shiny::tags$img(
        class = "history-item__image",
        src = image_url,
        alt = paste(role, item_name, sep = ": "),
        loading = "lazy"
      )
    ),
    shiny::div(
      class = "history-item__content",
      shiny::p(class = "history-item__role", role),
      shiny::p(class = "history-item__name", item_name)
    )
  )
}

wear_history_accordion_panel <- function(history_row) {
  worn_at <- history_row$worn_at[[1]]
  date_label <- paste(
    format(worn_at, "%B"),
    paste0(as.integer(format(worn_at, "%d")), ","),
    format(worn_at, "%Y")
  )

  bslib::accordion_panel(
    title = date_label,
    value = history_row$recommendation_id[[1]],
    shiny::div(
      class = "history-row__body",
      shiny::p(
        class = "history-row__weather",
        paste(stringr::str_to_sentence(history_row$weather_mode[[1]]), "weather")
      ),
      shiny::div(
        class = "history-row__items",
        wear_history_item(
          "Top",
          history_row$top_item_name[[1]],
          history_row$top_img_url[[1]]
        ),
        wear_history_item(
          "Bottom",
          history_row$bottom_item_name[[1]],
          history_row$bottom_img_url[[1]]
        ),
        wear_history_item(
          "Shoes",
          history_row$shoes_item_name[[1]],
          history_row$shoes_img_url[[1]]
        )
      )
    )
  )
}

wear_history_panel <- function(history) {
  history_content <- if (nrow(history) == 0L) {
    shiny::p(
      class = "history-panel__empty",
      "Outfits you mark as worn will appear here."
    )
  } else {
    panels <- lapply(
      seq_len(nrow(history)),
      function(row_number) {
        wear_history_accordion_panel(history[row_number, ])
      }
    )

    do.call(
      bslib::accordion,
      c(
        panels,
        list(
          open = FALSE,
          multiple = TRUE,
          class = "history-accordion"
        )
      )
    )
  }

  shiny::tags$section(
    class = "history-panel",
    shiny::div(
      class = "history-panel__heading",
      shiny::p(class = "eyebrow", "Wear history"),
      shiny::h2("What you wore")
    ),
    shiny::div(class = "history-list", history_content)
  )
}

app_notice <- function(message, type = c("info", "success", "error")) {
  type <- match.arg(type)

  shiny::div(
    class = paste("app-notice", paste0("app-notice--", type)),
    role = if (type == "error") "alert" else "status",
    message
  )
}
