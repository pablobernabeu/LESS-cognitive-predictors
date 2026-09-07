# =============================================================================
# 07_task_durations.R -- observed duration summaries for home and lab sessions
# =============================================================================
#
# The two manuscripts use the same duration summaries.  Home-task duration is the
# elapsed time between the first and last Gorilla event for a participant and task.
# Lab-phase duration is taken from OpenSesame's phase markers: the next phase marker
# ends a phase, and the last phase-specific event ends the final phase in a file.
#
# The raw data are read-only.  During local rendering the sparse checkout may omit
# them, so the reader falls back to the corresponding Git object.  On a full data
# or cluster checkout the ordinary file path is used instead.
# =============================================================================

if (!exists("data_path")) {
  source(here::here("_shared", "R", "00_paths.R"))
}
if (!exists("cognitive_ef_path")) {
  source(here::here("_shared", "R", "03_data_manifest.R"))
}

.les_duration_num <- function(x) {
  suppressWarnings(as.numeric(as.character(x)))
}

.les_duration_rel <- function(...) {
  # Git uses forward slashes even on Windows.
  gsub("\\\\", "/", file.path(...))
}

.les_duration_git_lines <- function(args) {
  # system2() on Windows does not reliably preserve arguments containing spaces
  # when it constructs the Git command line; quote those arguments explicitly.
  git_args <- vapply(c("-C", .les_root, args), function(x) {
    if (grepl("[[:space:]]", x)) shQuote(x) else x
  }, character(1))
  tryCatch(
    system2("git", git_args, stdout = TRUE, stderr = FALSE),
    error = function(e) character()
  )
}

.les_duration_list <- function(local_dir, rel_dir, pattern) {
  if (dir.exists(local_dir)) {
    files <- list.files(local_dir, pattern = pattern, full.names = TRUE,
                        recursive = FALSE)
    return(data.frame(path = files,
                      rel = .les_duration_rel("data", rel_dir, basename(files)),
                      stringsAsFactors = FALSE))
  }

  rel_dir <- .les_duration_rel("data", rel_dir)
  tracked <- .les_duration_git_lines(c("ls-tree", "-r", "--name-only", "HEAD", "--",
                                       rel_dir))
  tracked <- tracked[grepl(pattern, basename(tracked), ignore.case = TRUE)]
  data.frame(path = file.path(.les_root, tracked), rel = tracked,
             stringsAsFactors = FALSE)
}

.les_duration_read <- function(path, rel = NULL, cols = NULL) {
  read_one <- function(file) {
    if (is.null(cols)) {
      readr::read_csv(file, show_col_types = FALSE, progress = FALSE,
                      name_repair = "unique")
    } else {
      readr::read_csv(file, col_select = tidyselect::any_of(cols),
                      show_col_types = FALSE, progress = FALSE,
                      name_repair = "unique")
    }
  }
  if (file.exists(path)) {
    return(suppressWarnings(read_one(path)))
  }
  if (is.null(rel)) return(NULL)
  raw <- .les_duration_git_lines(c("show", paste0("HEAD:", rel)))
  if (!length(raw)) return(NULL)
  suppressWarnings(read_one(I(paste(raw, collapse = "\n"))))
}

.les_duration_key <- function() {
  key <- .les_duration_read(
    participant_key_csv(),
    .les_duration_rel("data", "Participant IDs and session progress.csv")
  )
  if (is.null(key)) return(NULL)
  key <- key[, intersect(c("participant_home_ID", "participant_lab_ID", "language"),
                         names(key)), drop = FALSE]
  if ("participant_home_ID" %in% names(key)) {
    key$participant_home_ID <- as.character(key$participant_home_ID)
  }
  if ("participant_lab_ID" %in% names(key)) {
    key$participant_lab_ID <- as.character(key$participant_lab_ID)
  }
  unique(key)
}

# Read a task's batch and named exports with the same batch-priority rule as the
# cognitive-index pipeline.  It prevents a participant present in both export kinds
# from contributing twice, which matters for a duration based on the first/last event.
.les_duration_task_raw <- function(files, task_pattern, cols = NULL) {
  if (!nrow(files)) return(NULL)
  is_batch <- grepl(paste0("^", task_pattern, " [0-9]+\\.csv$"),
                    basename(files$rel), ignore.case = TRUE)
  read_one <- function(i) .les_duration_read(files$path[i], files$rel[i], cols = cols)
  batch <- if (any(is_batch)) {
    dplyr::bind_rows(lapply(which(is_batch), read_one))
  } else NULL
  named <- if (any(!is_batch)) {
    dplyr::bind_rows(lapply(which(!is_batch), read_one))
  } else NULL
  if (is.null(batch)) return(dplyr::distinct(named))
  if (is.null(named)) return(dplyr::distinct(batch))
  id <- "Participant Public ID"
  if (id %in% names(batch) && id %in% names(named)) {
    named <- named[!(as.character(named[[id]]) %in% unique(as.character(batch[[id]]))), ,
                   drop = FALSE]
  }
  dplyr::distinct(dplyr::bind_rows(batch, named))
}

#' Extract one observed elapsed-time row per enrolled participant, session and task.
les_extract_home_task_durations <- function(sessions = c(1L, 5L)) {
  patterns <- c(stroop = "Stroop", digit_span = "digit span",
                asrt = "serial reaction time")
  rows <- list()
  k <- 0L
  for (session in sessions) {
    rel_dir <- .les_duration_rel("raw data", "executive functions",
                                 paste0("Session ", session))
    local_dir <- cognitive_ef_path(paste0("Session ", session))
    for (task in names(patterns)) {
      files <- .les_duration_list(local_dir, rel_dir,
                                   paste0(patterns[[task]], ".*\\.csv$"))
      raw <- .les_duration_task_raw(files, patterns[[task]],
                                    cols = c("Participant Public ID", "UTC Timestamp"))
      if (is.null(raw) ||
          !all(c("Participant Public ID", "UTC Timestamp") %in% names(raw))) next
      d <- data.frame(
        participant_home_ID = as.character(raw[["Participant Public ID"]]),
        event_ts_ms = .les_duration_num(raw[["UTC Timestamp"]]),
        stringsAsFactors = FALSE
      )
      d <- d[!is.na(d$participant_home_ID) & nzchar(d$participant_home_ID) &
               is.finite(d$event_ts_ms), , drop = FALSE]
      if (!nrow(d)) next
      d <- dplyr::distinct(d)
      one <- dplyr::summarise(
        dplyr::group_by(d, participant_home_ID),
        start_ms = min(event_ts_ms), end_ms = max(event_ts_ms),
        n_events = dplyr::n(), .groups = "drop"
      )
      one$duration_min <- (one$end_ms - one$start_ms) / 60000
      one$session <- as.integer(session)
      one$task <- task
      k <- k + 1L
      rows[[k]] <- one[, c("participant_home_ID", "session", "task",
                           "start_ms", "end_ms", "duration_min", "n_events")]
    }
  }
  out <- if (length(rows)) dplyr::bind_rows(rows) else data.frame()
  if (!nrow(out)) return(out)
  key <- .les_duration_key()
  if (!is.null(key) && all(c("participant_home_ID", "participant_lab_ID") %in% names(key))) {
    out <- dplyr::left_join(out, key, by = "participant_home_ID")
    out <- out[!is.na(out$participant_lab_ID), , drop = FALSE]
  } else {
    out$participant_lab_ID <- NA_character_
    out$language <- NA_character_
  }
  out$task <- factor(out$task, levels = names(patterns))
  out[order(out$session, out$task, out$participant_home_ID), , drop = FALSE]
}

.les_duration_phase_start <- c(
  pretraining = "time_PRETRAINING",
  training    = "time_TRAINING",
  test        = "time_TEST",
  experiment  = "time_EXPERIMENT"
)
.les_duration_phase_end <- list(
  pretraining = c("time_pretraining_loop", "time_pretraining_instructions",
                  "time_pretraining_instructions_en"),
  training    = c("time_training_sequence", "time_training_loop",
                  "time_training_instructions", "time_training_instructions_en"),
  test        = c("time_test_sequence", "time_process_Test_response",
                  "time_test_instructions", "time_test_instructions_en"),
  experiment  = c("time_experiment_sequence", "time_experiment_end_trigger",
                  "time_stop_recording", "time_end_of_task")
)

.les_duration_first <- function(d, col) {
  if (!col %in% names(d)) return(NA_real_)
  x <- .les_duration_num(d[[col]])
  x <- x[is.finite(x)]
  if (length(x)) min(x) else NA_real_
}

.les_duration_last <- function(d, cols, after = -Inf) {
  cols <- intersect(cols, names(d))
  if (!length(cols)) return(NA_real_)
  x <- unlist(lapply(cols, function(col) .les_duration_num(d[[col]])),
              use.names = FALSE)
  x <- x[is.finite(x) & x > after]
  if (length(x)) max(x) else NA_real_
}

#' Extract one observed duration row per participant, lab session and phase.
les_extract_lab_phase_durations <- function(sessions = c(2L, 3L, 4L, 6L)) {
  rows <- list()
  k <- 0L
  phase_order <- names(.les_duration_phase_start)
  for (session in sessions) {
    rel_dir <- .les_duration_rel("raw data", "behavioural data from lab sessions",
                                 paste0("Session ", session))
    local_dir <- behavioural_lab_path(paste0("Session ", session))
    files <- .les_duration_list(local_dir, rel_dir, "\\.csv$")
    if (!nrow(files)) next
    lab_cols <- unique(c(unname(.les_duration_phase_start),
                         unlist(.les_duration_phase_end, use.names = FALSE)))
    for (i in seq_len(nrow(files))) {
      d <- .les_duration_read(files$path[i], files$rel[i], cols = lab_cols)
      if (is.null(d) || !nrow(d)) next
      subject <- sub("^subject-([0-9]+).*$", "\\1", basename(files$rel[i]),
                     ignore.case = TRUE)
      if (!grepl("^[0-9]+$", subject) && "subject_nr" %in% names(d)) {
        subject <- as.character(d$subject_nr[which(is.finite(.les_duration_num(d$subject_nr)))[1]])
      }
      if (!grepl("^[0-9]+$", subject)) next

      starts <- vapply(.les_duration_phase_start,
                       function(col) .les_duration_first(d, col), numeric(1))
      for (phase in phase_order) {
        start <- starts[[phase]]
        if (!is.finite(start)) next
        idx <- match(phase, phase_order)
        later <- if (idx < length(phase_order)) starts[(idx + 1L):length(phase_order)] else numeric()
        later <- later[is.finite(later) & later > start]
        if (length(later)) {
          end <- min(later)
          boundary <- "next phase start"
        } else {
          end <- .les_duration_last(d, .les_duration_phase_end[[phase]], after = start)
          boundary <- "last phase event"
        }
        if (!is.finite(end) || end <= start) next
        k <- k + 1L
        rows[[k]] <- data.frame(
          participant_lab_ID = as.character(as.integer(subject)),
          session = as.integer(session), phase = phase,
          start_ms = start, end_ms = end,
          duration_min = (end - start) / 60000,
          boundary = boundary, source_file = basename(files$rel[i]),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  out <- if (length(rows)) dplyr::bind_rows(rows) else data.frame()
  if (!nrow(out)) return(out)
  key <- .les_duration_key()
  if (!is.null(key) && "participant_lab_ID" %in% names(key)) {
    key$participant_lab_ID <- as.character(key$participant_lab_ID)
    out <- dplyr::left_join(out, key, by = "participant_lab_ID")
  } else {
    out$participant_home_ID <- NA_character_
    out$language <- NA_character_
  }
  out$phase <- factor(out$phase, levels = phase_order)
  out[order(out$session, out$phase, out$participant_lab_ID), , drop = FALSE]
}

# Write to both manuscript result folders so either paper can render independently.
les_write_task_duration_artifacts <- function() {
  home <- les_extract_home_task_durations()
  lab  <- les_extract_lab_phase_durations()
  targets <- list(
    home = c(paper1_results("_task_durations_home.csv"),
             paper2_results("_task_durations_home.csv")),
    lab  = c(paper1_results("_task_durations_lab.csv"),
             paper2_results("_task_durations_lab.csv"))
  )
  for (p in c(targets$home, targets$lab)) les_assert_readonly_data(p)
  for (p in targets$home) readr::write_csv(home, p, na = "")
  for (p in targets$lab)  readr::write_csv(lab, p, na = "")
  message(sprintf("[durations] home rows=%d; lab rows=%d", nrow(home), nrow(lab)))
  invisible(list(home = home, lab = lab))
}

# Inline prose for the main text. Keep the reported medians tied to the same
# participant-level artefacts used by the figures rather than transcribing them.
les_task_duration_median_text <- function(home, lab, digits = 2) {
  if (is.null(home) || !nrow(home) || is.null(lab) || !nrow(lab)) {
    return("Median task and phase durations will be reported once the duration artefacts are available.")
  }
  fmt <- function(x) formatC(stats::median(x[is.finite(x)]),
                              format = "f", digits = digits)
  home_med <- function(session, task) {
    x <- .les_duration_num(home$duration_min[
      as.character(home$session) == as.character(session) &
        as.character(home$task) == task])
    fmt(x)
  }
  lab_med <- function(session, phase) {
    x <- .les_duration_num(lab$duration_min[
      as.character(lab$session) == as.character(session) &
        as.character(lab$phase) == phase])
    fmt(x)
  }
  paste0(
    "The median home-task durations were ",
    home_med(1, "stroop"), " min for Stroop, ",
    home_med(1, "digit_span"), " min for digit span and ",
    home_med(1, "asrt"), " min for ASRT in Session 1, and ",
    home_med(5, "stroop"), ", ", home_med(5, "digit_span"), " and ",
    home_med(5, "asrt"), " min, respectively, in Session 5. Median laboratory-phase ",
    "durations (pretraining, training, test and experiment) were ",
    lab_med(2, "pretraining"), ", ", lab_med(2, "training"), ", ",
    lab_med(2, "test"), " and ", lab_med(2, "experiment"), " min in Session 2; ",
    lab_med(3, "pretraining"), ", ", lab_med(3, "training"), ", ",
    lab_med(3, "test"), " and ", lab_med(3, "experiment"), " min in Session 3; ",
    lab_med(4, "training"), ", ", lab_med(4, "test"), " and ",
    lab_med(4, "experiment"), " min for training, test and experiment in Session 4, ",
    "where pretraining was not recorded; and ", lab_med(6, "experiment"),
    " min for the experiment in Session 6, where the other phases were not recorded."
  )
}

# Compact ggplot figures used in both manuscripts.  Keeping the geometry here makes
# the two papers use identical axes, facet order and dispersion summaries.
les_task_duration_home_plot <- function(data, base_size = 9) {
  if (is.null(data) || !nrow(data)) {
    return(ggplot2::ggplot() + ggplot2::theme_void() +
             ggplot2::annotate("text", x = 0, y = 0,
                               label = "Home-task duration data pending"))
  }
  d <- data |>
    dplyr::filter(is.finite(duration_min), session %in% c(1, 5)) |>
    dplyr::mutate(
      task = factor(task, levels = c("stroop", "digit_span", "asrt"),
                    labels = c("Stroop", "Digit span", "ASRT")),
      session = factor(session, levels = c(1, 5),
                       labels = c("Session 1", "Session 5")))
  if (!nrow(d)) {
    return(ggplot2::ggplot() + ggplot2::theme_void() +
             ggplot2::annotate("text", x = 0, y = 0,
                               label = "Home-task duration data pending"))
  }
  ggplot2::ggplot(d, ggplot2::aes(x = task, y = duration_min)) +
    ggplot2::geom_boxplot(width = 0.56, linewidth = 0.35, outlier.size = 0.7,
                          outlier.stroke = 0.2) +
    ggplot2::scale_x_discrete(drop = FALSE) +
    ggplot2::scale_y_log10(expand = ggplot2::expansion(mult = c(0.02, 0.08))) +
    ggplot2::labs(x = NULL, y = "Task duration (minutes; log scale)") +
    ggplot2::facet_wrap(~ session, nrow = 1, drop = FALSE) +
    les_theme(base_size) +
    ggplot2::theme(legend.position = "none",
                   strip.text = ggplot2::element_text(face = "bold", size = base_size),
                   axis.text.x = ggplot2::element_text(margin = ggplot2::margin(t = 3)),
                   plot.margin = ggplot2::margin(4, 8, 4, 8))
}

les_task_duration_lab_plot <- function(data, base_size = 9) {
  if (is.null(data) || !nrow(data)) {
    return(ggplot2::ggplot() + ggplot2::theme_void() +
             ggplot2::annotate("text", x = 0, y = 0,
                               label = "Lab-phase duration data pending"))
  }
  d <- data |>
    dplyr::filter(is.finite(duration_min), session %in% c(2, 3, 4, 6)) |>
    dplyr::mutate(
      phase = factor(phase, levels = c("pretraining", "training", "test", "experiment"),
                     labels = c("Pretraining", "Training", "Test", "Experiment")),
      session = factor(session, levels = c(2, 3, 4, 6),
                       labels = c("Session 2", "Session 3", "Session 4", "Session 6")))
  if (!nrow(d)) {
    return(ggplot2::ggplot() + ggplot2::theme_void() +
             ggplot2::annotate("text", x = 0, y = 0,
                               label = "Lab-phase duration data pending"))
  }
  ggplot2::ggplot(d, ggplot2::aes(x = phase, y = duration_min)) +
    ggplot2::geom_boxplot(width = 0.56, linewidth = 0.35, outlier.size = 0.7,
                          outlier.stroke = 0.2) +
    ggplot2::scale_x_discrete(drop = FALSE) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.02, 0.08))) +
    ggplot2::labs(x = NULL, y = "Phase duration (minutes)") +
    ggplot2::facet_wrap(~ session, nrow = 1, drop = FALSE) +
    les_theme(base_size) +
    ggplot2::theme(legend.position = "none",
                   strip.text = ggplot2::element_text(face = "bold", size = base_size),
                   axis.text.x = ggplot2::element_text(angle = 25, hjust = 1, vjust = 1,
                                                       margin = ggplot2::margin(t = 3)),
                   plot.margin = ggplot2::margin(4, 8, 4, 8))
}
