app_server <- function(
  input,
  output,
  session,
  connection_factory = db_connect_local_app
) {
  connection <- connection_factory()
  session$onSessionEnded(function() db_disconnect(connection))

  app_state <- shiny::reactiveVal(
    read_recommendation_state(connection)
  )
  busy <- shiny::reactiveVal(FALSE)
  notice <- shiny::reactiveVal(NULL)

  output$weather_mode <- shiny::renderUI({
    weather_mode_indicator(
      app_state()$settings$weather_mode[[1]]
    )
  })

  output$notice <- shiny::renderUI({
    current_notice <- notice()
    if (is.null(current_notice)) {
      return(NULL)
    }

    app_notice(current_notice$message, current_notice$type)
  })

  output$decision_view <- shiny::renderUI({
    state <- app_state()

    if (nrow(state$recommendation) == 0L) {
      empty_decision_panel(
        state$settings$weather_mode[[1]],
        busy = busy()
      )
    } else {
      active_decision_panel(
        state$recommendation,
        busy = busy()
      )
    }
  })

  shiny::observeEvent(input$choose_outfit, {
    state_at_click <- app_state()
    busy(TRUE)
    notice(NULL)
    on.exit(busy(FALSE), add = TRUE)

    result <- tryCatch(
      choose_active_recommendation(
        connection,
        starting_state_version =
          state_at_click$settings$state_version[[1]],
        starting_active_recommendation_id =
          state_at_click$settings$active_recommendation_id[[1]]
      ),
      error = function(error) error
    )

    if (inherits(result, "error")) {
      notice(list(
        type = "error",
        message = "The outfit could not be saved; try again."
      ))
      return()
    }

    app_state(result$state)
    notice(list(
      type = if (result$stale) "info" else "success",
      message = if (result$stale) {
        "The current recommendation was reloaded."
      } else {
        "Your outfit is ready."
      }
    ))
  }, ignoreInit = TRUE)

  shiny::observeEvent(input$reroll_outfit, {
    state_at_click <- app_state()
    busy(TRUE)
    notice(NULL)
    on.exit(busy(FALSE), add = TRUE)

    result <- tryCatch(
      reroll_active_recommendation(
        connection,
        starting_state_version =
          state_at_click$settings$state_version[[1]],
        starting_active_recommendation_id =
          state_at_click$settings$active_recommendation_id[[1]]
      ),
      error = function(error) error
    )

    if (inherits(result, "error")) {
      notice(list(
        type = "error",
        message = "Another outfit could not be saved; try again."
      ))
      return()
    }

    app_state(result$state)
    notice(list(
      type = "info",
      message = if (result$stale) {
        "The current recommendation was reloaded."
      } else {
        "Here’s another option."
      }
    ))
  }, ignoreInit = TRUE)
}
