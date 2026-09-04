# =============================================================================
# paper_2_plasticity/scripts/10_extract_descriptives.R
# Phase 3 -- Raw-data DESCRIPTIVES for the Paper 2 manuscript.
# =============================================================================
#
# PURPOSE
# -------
# This script extracts observed, raw-data descriptives that the manuscript
# (paper_2_neuroplasticity.qmd) injects into its text and tables and uses for the
# descriptive figures (predictor distributions, correlation heatmap, resting-state PSD,
# and the observed grammaticality-judgement accuracy trajectory), independently of the
# Bayesian models.
#
# INPUTS (all read-only; produced by scripts 01-03)
#   paper_2_plasticity/data_derived/cognitive_indices.rds     (01: S1/S5 indices)
#   paper_2_plasticity/data_derived/resting_state_eeg.rds     (03: S2 band power + IAF)
#   paper_2_plasticity/data_derived/learning_trajectory.rds   (02: trial-level accuracy)
#   data/raw data/executive functions/Session 1/*.csv         (task-structure specs)
#   data/raw data/EEG/Session 2/Export/*_RS_eyes_*.{vhdr,txt} (ROI-averaged PSD)
#
# OUTPUTS (paper2_results(); all prefixed "_" like the other results tables)
#   _cognitive_descriptives.csv
#   _predictor_descriptives.csv
#   _predictor_values.csv          long-format raw predictor values, one row per
#                                  participant x predictor, for the distribution figure
#   _predictor_correlations.csv
#   _rseeg_descriptives.csv
#   _resting_state_psd.csv
#   _accuracy_trajectory_descriptives.csv
#   _task_specs.csv
#
# DESIGN NOTES
# ------------
# * The ROI-averaged Welch PSD (which script 03 computes then discards, keeping only
#   band integrals + IAF) is re-computed here from the SAME base-R BrainVision reader
#   and the SAME Welch estimator (2-s Hann window, 50% overlap) that 03 uses, so the
#   persisted PSD is exactly the spectrum underlying 03's band powers. 03 is not
#   modified destructively; its reader/Welch helpers are sourced without side effects.
# * "Predictors" here are the baseline (Session 1 cognitive; Session 2 = the only
#   resting session, eyes-closed) Part-A predictors; eyes-closed is the analysed
#   resting condition (alpha suppressed eyes-open), matching 03/04 and the Methods.
#
# USAGE
#   Rscript --vanilla paper_2_plasticity/scripts/10_extract_descriptives.R
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "03_data_manifest.R"))
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  library(dplyr)
  library(tidyr)
  library(readr)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# -----------------------------------------------------------------------------
# Reuse 03's readers + Welch estimator WITHOUT running its extraction. 03 guards
# its driver with `if (sys.nframe() == 0L)`, so sourcing it here only defines the
# helper functions (.parse_vhdr, .read_bv_ascii, welch_psd, les_band_power, les_iaf,
# LES_RS_POSTERIOR); nothing is written.
# -----------------------------------------------------------------------------
source(here::here("paper_2_plasticity", "scripts", "03_extract_resting_state_eeg.R"))

# The six-number descriptive summary reused by every table below.
.six <- function(x) {
  x <- x[is.finite(x)]
  tibble(n = length(x),
         mean = mean(x), sd = stats::sd(x),
         median = stats::median(x),
         min = suppressWarnings(min(x)), max = suppressWarnings(max(x)))
}

# The eyes-closed / eyes-open band-power + IAF variables, in a fixed order.
.RS_VARS <- c("delta", "theta", "alpha", "beta", "gamma", "iaf")

# =============================================================================
# (1) _cognitive_descriptives.csv  --  per session x index six-number summary
# =============================================================================
write_cognitive_descriptives <- function(cog) {
  long <- cog %>%
    filter(session %in% LES_P2_COG_SESSIONS) %>%
    select(session, digit_span, stroop_interference, asrt_learning) %>%
    pivot_longer(-session, names_to = "index", values_to = "value")
  out <- long %>%
    group_by(session, index) %>%
    group_modify(~ .six(.x$value)) %>%
    ungroup() %>%
    arrange(match(index, c("digit_span", "stroop_interference", "asrt_learning")), session)
  f <- paper2_results("_cognitive_descriptives.csv")
  les_assert_readonly_data(f); readr::write_csv(out, f)
  list(path = f, tbl = out)
}

# =============================================================================
# (2) _predictor_descriptives.csv  --  baseline Part-A predictors
#     (S1 cognition + S2 eyes-closed rs-EEG bands + IAF), six-number summary
# =============================================================================
.build_predictor_frame <- function(cog, rseeg) {
  # Baseline cognition = Session 1, keyed on participant_lab_ID.
  cog_s1 <- cog %>%
    filter(session == 1, !is.na(participant_lab_ID)) %>%
    transmute(participant_lab_ID = as.integer(participant_lab_ID),
              digit_span, stroop_interference, asrt_learning)
  # Baseline rs-EEG = eyes-closed (the analysed resting condition).
  rs_ec <- rseeg %>%
    filter(condition == "eyes_closed") %>%
    transmute(participant_lab_ID = as.integer(participant_lab_ID),
              delta, theta, alpha, beta, gamma, iaf)
  # Inner join: participants with BOTH a baseline battery and eyes-closed rs-EEG
  # (this is the joint predictor frame the Part-A model conditions on).
  inner_join(cog_s1, rs_ec, by = "participant_lab_ID")
}

write_predictor_descriptives <- function(pred) {
  vars <- c("digit_span", "stroop_interference", "asrt_learning", .RS_VARS)
  out <- pred %>%
    select(all_of(vars)) %>%
    pivot_longer(everything(), names_to = "predictor", values_to = "value") %>%
    group_by(predictor) %>%
    group_modify(~ .six(.x$value)) %>%
    ungroup() %>%
    arrange(match(predictor, vars))
  f <- paper2_results("_predictor_descriptives.csv")
  les_assert_readonly_data(f); readr::write_csv(out, f)
  list(path = f, tbl = out)
}

# =============================================================================
# (3) _predictor_correlations.csv  --  Pearson r over the z-scored joint frame
#     (long: var1, var2, r, n). Pairwise-complete, computed on the standardised
#     predictors; standardising does not change Pearson r but matches how the
#     predictors enter the model and keeps the frame self-documenting.
# =============================================================================
write_predictor_correlations <- function(pred) {
  vars <- c("digit_span", "stroop_interference", "asrt_learning", .RS_VARS)
  Z <- pred %>% select(all_of(vars)) %>% mutate(across(everything(), ~ as.numeric(scale(.))))
  R <- suppressWarnings(stats::cor(Z, use = "pairwise.complete.obs", method = "pearson"))
  # pairwise n per cell (count of jointly non-missing rows)
  Nmat <- outer(vars, vars, Vectorize(function(a, b)
    sum(is.finite(Z[[a]]) & is.finite(Z[[b]]))))
  out <- expand.grid(var1 = vars, var2 = vars, stringsAsFactors = FALSE) %>%
    mutate(r = as.numeric(R[cbind(match(var1, vars), match(var2, vars))]),
           n = as.integer(Nmat[cbind(match(var1, vars), match(var2, vars))]))
  f <- paper2_results("_predictor_correlations.csv")
  les_assert_readonly_data(f); readr::write_csv(out, f)
  list(path = f, tbl = out)
}

# =============================================================================
# (4) _rseeg_descriptives.csv  --  band power + IAF for eyes-closed AND eyes-open,
#     plus the count of participants with a resolvable alpha peak (7-13 Hz).
# =============================================================================
write_rseeg_descriptives <- function(rseeg) {
  out <- rseeg %>%
    filter(condition %in% c("eyes_closed", "eyes_open")) %>%
    select(condition, all_of(.RS_VARS)) %>%
    pivot_longer(-condition, names_to = "band", values_to = "value") %>%
    group_by(condition, band) %>%
    group_modify(~ .six(.x$value)) %>%
    ungroup() %>%
    arrange(match(condition, c("eyes_closed", "eyes_open")),
            match(band, .RS_VARS))

  # A resolvable alpha peak = a finite IAF within the 7-13 Hz search range. les_iaf()
  # returns the arg-max frequency in [7,13]; NA only when no bins fall in-range, so
  # here we additionally require the reported IAF to sit strictly inside the band
  # (i.e. not pinned to an edge), which is the operational "peak found" criterion.
  peak <- rseeg %>%
    filter(condition %in% c("eyes_closed", "eyes_open")) %>%
    mutate(has_peak = is.finite(iaf) & iaf > 7 & iaf < 13) %>%
    group_by(condition) %>%
    summarise(n_participants_with_resolvable_alpha_peak = sum(has_peak),
              n = dplyr::n(), .groups = "drop")
  # Emit peak counts as extra rows (band == "alpha_peak_count"); value carries the count.
  peak_rows <- peak %>%
    transmute(condition, band = "alpha_peak_count",
              n = n,
              mean = NA_real_, sd = NA_real_, median = NA_real_,
              min = NA_real_, max = NA_real_,
              n_participants_with_resolvable_alpha_peak) %>%
    select(condition, band, n, mean, sd, median, min, max,
           n_participants_with_resolvable_alpha_peak)

  out <- out %>%
    mutate(n_participants_with_resolvable_alpha_peak = NA_integer_) %>%
    bind_rows(peak_rows)

  f <- paper2_results("_rseeg_descriptives.csv")
  les_assert_readonly_data(f); readr::write_csv(out, f)
  list(path = f, tbl = out, peak = peak)
}

# =============================================================================
# (5) _resting_state_psd.csv  --  ROI-averaged Welch PSD that 03 discards.
#     Re-computed here with 03's reader + welch_psd() (2-s Hann, 50% overlap),
#     averaged over the 8 occipito-parietal channels, per participant x condition,
#     restricted to 1-45 Hz. This is exactly the spectrum underlying 03's bands.
# =============================================================================
.roi_psd_one <- function(vhdr, fmax = 45) {
  h   <- .parse_vhdr(vhdr)
  sig <- .read_bv_ascii(vhdr, h)
  post <- intersect(LES_RS_POSTERIOR, colnames(sig))
  if (!length(post)) return(NULL)
  psds <- Filter(Negate(is.null), lapply(post, function(ch) welch_psd(sig[, ch], h$srate)))
  if (!length(psds)) return(NULL)
  freqs <- psds[[1]]$freqs
  pw <- rowMeans(matrix(unlist(lapply(psds, `[[`, "power")), ncol = length(psds)))
  keep <- which(freqs >= 1 & freqs <= fmax)
  tibble(freq_hz = freqs[keep], power = pw[keep])
}

write_resting_state_psd <- function() {
  root  <- data_path("raw data", "EEG")
  vhdrs <- list.files(root, pattern = "_RS_eyes_(open|closed)\\.vhdr$",
                      recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  rows <- list()
  for (vhdr in vhdrs) {
    sess <- suppressWarnings(as.integer(sub(".*/Session[ _]?([0-9]+)/.*", "\\1", vhdr)))
    if (is.na(sess) || !(sess %in% LES_P2_NEURAL_SESSIONS)) next
    pid  <- suppressWarnings(as.integer(sub("^([0-9]+)_RS.*", "\\1", basename(vhdr))))
    cond <- if (grepl("eyes_open", vhdr, ignore.case = TRUE)) "eyes_open" else "eyes_closed"
    psd <- tryCatch(.roi_psd_one(vhdr), error = function(e) { message("  skip ", basename(vhdr), ": ", conditionMessage(e)); NULL })
    if (is.null(psd)) next
    rows[[length(rows) + 1]] <- psd %>%
      mutate(participant_lab_ID = pid, condition = cond) %>%
      select(participant_lab_ID, condition, freq_hz, power)
  }
  out <- bind_rows(rows) %>% arrange(participant_lab_ID, condition, freq_hz)
  f <- paper2_results("_resting_state_psd.csv")
  les_assert_readonly_data(f); readr::write_csv(out, f)
  list(path = f, tbl = out)
}

# =============================================================================
# (6) _accuracy_trajectory_descriptives.csv  --  observed grammaticality-judgement
#     accuracy. Three blocks in one long table (distinguished by `level`):
#       level == "group_cell": per session x property x language cell means
#                              (n trials, mean_accuracy, se)
#       level == "participant_cell": per participant x session x property x language
#                              means, for a per-property spaghetti layer
#       level == "participant": per participant x session means (for spaghetti),
#                              carrying property/language where they are constant.
# =============================================================================
write_accuracy_trajectory <- function(traj) {
  has_prop <- "grammatical_property" %in% names(traj)
  has_lang <- "mini_language" %in% names(traj)

  # Binomial SE of a proportion, used only for the per-participant blocks (where the
  # trial IS the sampling unit for that participant's own mean).
  se_prop <- function(p, n) ifelse(n > 0, sqrt(p * (1 - p) / n), NA_real_)

  group_by_cols <- c("session", if (has_prop) "grammatical_property", if (has_lang) "mini_language")

  # Per participant x cell means. This is the unit of analysis for any interval placed
  # on a GROUP mean: participants, not trials, are the sampling unit. Also emitted in
  # its own right (level == "participant_cell") so a per-property spaghetti layer is
  # possible -- the pooled "participant" block below carries no property key.
  part_cell <- traj %>%
    group_by(across(all_of(c("participant_lab_ID", group_by_cols)))) %>%
    summarise(n = dplyr::n(),
              mean_accuracy = mean(correct, na.rm = TRUE),
              .groups = "drop")

  # Group cell: mean of participant means, with a BETWEEN-PARTICIPANT standard error.
  # Computing sqrt(p(1-p)/n_trials) here instead would treat ~85 trials from each of
  # ~30 participants as independent Bernoulli draws and understate the interval several-
  # fold (pseudoreplication), manufacturing apparent separation between the two
  # mini-languages. `se` is computed before `mean_accuracy` is overwritten.
  group_cell <- part_cell %>%
    group_by(across(all_of(group_by_cols))) %>%
    summarise(n = sum(n),
              n_participants = dplyr::n(),
              se = stats::sd(mean_accuracy, na.rm = TRUE) / sqrt(dplyr::n()),
              mean_accuracy = mean(mean_accuracy, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(level = "group_cell",
           participant_lab_ID = NA_character_) %>%
    { if (!has_prop) mutate(., grammatical_property = NA_character_) else . } %>%
    { if (!has_lang) mutate(., mini_language = NA_character_) else . }

  # Per-participant per-session means (spaghetti). Property/language attached where a
  # participant contributes only one (language is fixed per participant; property is
  # pooled, so it is left NA at the participant level and read from group_cell instead).
  part <- traj %>%
    group_by(participant_lab_ID, session) %>%
    summarise(n = dplyr::n(),
              mean_accuracy = mean(correct, na.rm = TRUE),
              mini_language = if (has_lang) dplyr::first(as.character(mini_language)) else NA_character_,
              .groups = "drop") %>%
    mutate(se = se_prop(mean_accuracy, n),
           level = "participant",
           grammatical_property = NA_character_,
           participant_lab_ID = as.character(participant_lab_ID))

  part_cell_out <- part_cell %>%
    mutate(se = se_prop(mean_accuracy, n),
           level = "participant_cell",
           participant_lab_ID = as.character(participant_lab_ID)) %>%
    { if (!has_prop) mutate(., grammatical_property = NA_character_) else . } %>%
    { if (!has_lang) mutate(., mini_language = NA_character_) else . }

  out <- bind_rows(
    group_cell %>% select(level, session, grammatical_property, mini_language,
                          participant_lab_ID, n, mean_accuracy, se),
    part_cell_out %>% select(level, session, grammatical_property, mini_language,
                             participant_lab_ID, n, mean_accuracy, se),
    part %>% select(level, session, grammatical_property, mini_language,
                    participant_lab_ID, n, mean_accuracy, se)
  ) %>% arrange(level, session, grammatical_property, mini_language, participant_lab_ID)

  f <- paper2_results("_accuracy_trajectory_descriptives.csv")
  les_assert_readonly_data(f); readr::write_csv(out, f)
  list(path = f, tbl = out, has_prop = has_prop, has_lang = has_lang)
}

# =============================================================================
# (7) _task_specs.csv  --  OBSERVED task structure from the raw Session-1 exports.
#     Columns: task, spec, value, note. Values are read from the data wherever possible,
#     so the manuscript can be corrected where it disagrees (e.g. ASRT trials/block).
#     A few rows instead carry a preregistered design value, and say so in `note`;
#     currently only asrt/trials_per_block, whose observed counterpart is emitted
#     separately as modal_trials_per_block.
# =============================================================================
.read_many_csv <- function(files)
  dplyr::bind_rows(lapply(files, function(f)
    suppressWarnings(readr::read_csv(f, show_col_types = FALSE, progress = FALSE))))

# batch exports only (systematic export; avoids double-counting named re-exports)
.s1_batch_files <- function(pattern) {
  dir <- cognitive_ef_path("Session 1")
  list.files(dir, pattern = paste0("^", pattern, " [0-9]+\\.csv$"),
             full.names = TRUE, recursive = FALSE, ignore.case = TRUE)
}

.modal <- function(x) { t <- sort(table(x), decreasing = TRUE); as.numeric(names(t)[1]) }

write_task_specs <- function() {
  rows <- list()
  add <- function(task, spec, value, note = "")
    rows[[length(rows) + 1]] <<- tibble(task = task, spec = spec,
                                        value = as.character(value), note = note)

  # --- ASRT (alternating serial reaction time) -----------------------------
  asrt <- .read_many_csv(.s1_batch_files("serial reaction time"))
  if (nrow(asrt) && "block" %in% names(asrt)) {
    asrt <- asrt %>% filter(!is.na(block))
    n_blocks <- dplyr::n_distinct(asrt$block)
    tpb <- asrt %>% group_by(`Participant Public ID`, block) %>%
      summarise(n = dplyr::n(), .groups = "drop")
    modal_tpb <- .modal(tpb$n)
    add("asrt", "n_blocks", n_blocks,
        "distinct block values in the Session-1 ASRT exports")
    add("asrt", "modal_trials_per_block", modal_tpb,
        sprintf("modal trials/block observed in the raw export (range %d-%d; includes a leading practice triplet)",
                min(tpb$n), max(tpb$n)))
    add("asrt", "trials_per_block", 85,
        "preregistered design value (85 scored trials/block); the manuscript previously stated 80 in error")
  }

  # --- Digit span ----------------------------------------------------------
  ds <- .read_many_csv(.s1_batch_files("digit span"))
  if (nrow(ds) && "Zone Type" %in% names(ds)) {
    ds_scored <- ds %>% filter(`Zone Type` == "response_text_entry")
    modal_trials <- .modal(dplyr::count(ds_scored, `Participant Public ID`)$n)
    add("digit_span", "scored_trials", modal_trials,
        "modal number of scored response_text_entry trials/participant (expected 48)")
  }

  # --- Stroop --------------------------------------------------------------
  st <- .read_many_csv(.s1_batch_files("Stroop"))
  if (nrow(st) && "Zone Type" %in% names(st)) {
    st_resp <- st %>% filter(`Zone Type` == "response_keyboard")
    # Test trials only: exclude practice (Practice==1 / display=="Practice Trials").
    is_practice <- rep(FALSE, nrow(st_resp))
    if ("Practice" %in% names(st_resp))
      is_practice <- is_practice | st_resp$Practice %in% c(1, "1", TRUE, "true", "TRUE")
    if ("display" %in% names(st_resp))
      is_practice <- is_practice | grepl("practice", as.character(st_resp$display), ignore.case = TRUE)
    st_test <- st_resp[!is_practice, , drop = FALSE]
    modal_trials <- .modal(dplyr::count(st_test, `Participant Public ID`)$n)
    add("stroop", "test_trials", modal_trials,
        "modal test trials/participant, excluding practice (expected 100)")
    if ("Congruency" %in% names(st_test)) {
      cong <- st_test %>%
        mutate(cong = ifelse(Congruency %in% c(1, "1"), "congruent", "incongruent")) %>%
        group_by(`Participant Public ID`, cong) %>% summarise(n = dplyr::n(), .groups = "drop")
      add("stroop", "congruent_trials", .modal(cong$n[cong$cong == "congruent"]),
          "modal congruent test trials/participant (expected 50)")
      add("stroop", "incongruent_trials", .modal(cong$n[cong$cong == "incongruent"]),
          "modal incongruent test trials/participant (expected 50)")
    }
  }

  out <- dplyr::bind_rows(rows)
  f <- paper2_results("_task_specs.csv")
  les_assert_readonly_data(f); readr::write_csv(out, f)
  list(path = f, tbl = out)
}

# =============================================================================
# Driver
# =============================================================================
extract_descriptives <- function() {
  cog   <- readRDS(paper2_derived("cognitive_indices.rds"))
  rseeg <- readRDS(paper2_derived("resting_state_eeg.rds"))
  traj  <- readRDS(paper2_derived("learning_trajectory.rds"))
  pred  <- .build_predictor_frame(cog, rseeg)

  # Raw (long) predictor values, so the manuscript can show the distributions.
  pv <- pred %>% tidyr::pivot_longer(-participant_lab_ID, names_to = "predictor",
                                     values_to = "value") %>% dplyr::filter(!is.na(value))
  { f <- paper2_results("_predictor_values.csv"); les_assert_readonly_data(f); readr::write_csv(pv, f) }

  list(
    cognitive   = write_cognitive_descriptives(cog),
    predictor   = write_predictor_descriptives(pred),
    correlation = write_predictor_correlations(pred),
    rseeg       = write_rseeg_descriptives(rseeg),
    psd         = write_resting_state_psd(),
    accuracy    = write_accuracy_trajectory(traj),
    task_specs  = write_task_specs(),
    pred_frame  = pred
  )
}

# =============================================================================
# Entry point + validation
# =============================================================================
.run <- function() {
  res <- extract_descriptives()

  cat("\n================= _cognitive_descriptives.csv =================\n")
  print(as.data.frame(res$cognitive$tbl), digits = 4)

  cat("\n================= _predictor_descriptives.csv =================\n")
  cat("joint predictor frame N =", nrow(res$pred_frame), "\n")
  print(as.data.frame(res$predictor$tbl), digits = 4)

  cat("\n================= _predictor_correlations.csv (head) =========\n")
  print(head(as.data.frame(res$correlation$tbl), 12), digits = 3)

  cat("\n================= _rseeg_descriptives.csv ====================\n")
  print(as.data.frame(res$rseeg$tbl), digits = 4)
  cat("\nResolvable alpha peak (7-13 Hz) by condition:\n")
  print(as.data.frame(res$rseeg$peak))

  cat("\n================= _resting_state_psd.csv =====================\n")
  psd <- res$psd$tbl
  cat("rows:", nrow(psd),
      "| participants:", dplyr::n_distinct(psd$participant_lab_ID),
      "| conditions:", paste(sort(unique(psd$condition)), collapse = "/"),
      "| freq range:", sprintf("%.2f-%.2f Hz", min(psd$freq_hz), max(psd$freq_hz)), "\n")
  print(head(as.data.frame(psd)))

  cat("\n================= _accuracy_trajectory_descriptives.csv =======\n")
  cat("has grammatical_property:", res$accuracy$has_prop,
      "| has mini_language:", res$accuracy$has_lang, "\n")
  cat("group_cell rows (session x property x language):\n")
  print(as.data.frame(res$accuracy$tbl %>% filter(level == "group_cell")), digits = 3)
  cat("\nparticipant-level rows:",
      sum(res$accuracy$tbl$level == "participant"), "\n")

  cat("\n================= _task_specs.csv ============================\n")
  print(as.data.frame(res$task_specs$tbl))

  cat("\n[descriptives] all CSVs written to", paper2_results(), "\n")
  message("[descriptives] done.")
}

if (sys.nframe() == 0L) .run()
