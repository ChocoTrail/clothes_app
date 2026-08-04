weather_mode_indicator <- function(weather_mode) {
  shiny::div(
    class = "weather-mode",
    shiny::span(class = "weather-mode__label", "Weather mode"),
    shiny::span(
      class = "weather-mode__value",
      stringr::str_to_sentence(weather_mode)
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

active_decision_panel <- function(recommendation) {
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
    )
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
