# =============================================================================
# paper_2_plasticity/scripts/02_extract_learning_trajectory.R
# Phase 3a -- Assemble the longitudinal LEARNING-OUTCOME dataset for Paper 2.
# =============================================================================
#
# LEARNING OUTCOME (established 2026-06-10 from a dedicated methods review + user
# confirmation): the learning outcome is the longitudinal grammaticality-JUDGEMENT
# accuracy across sessions (S2/3/4/6) -- the scored test of what was learned -- to
# be modelled JOINTLY (not reduced to a per-participant slope). The training/feedback
# phase is NOT cleanly row-logged in the OpenSesame logs (it survives only as summary
# counters), whereas the judgement-test accuracy is clean and already validated by
# Paper 1. See the Part A section of paper_2_plasticity/README.md for the full rationale
# and citations.
#
# WHY REUSE build_paper1_accuracy()
# ---------------------------------
# Paper 1's 02_extract_accuracy.R already isolates and validates the scored
# judgement trials (rows with an explicit grammatical_property), with the documented
# RT filter, de-duplication, canonical property/grammaticality mapping, language-by-
# parity coding and 0/1/2/3 growth-curve session coding. Sourcing it defines
# build_paper1_accuracy() WITHOUT side effects (its .run() is guarded by
# `if (sys.nframe() == 0L)`), so we reuse the validated extraction verbatim and POOL
# across properties here (property enters the Part A model as a factor).
#
# WHAT THIS PRODUCES
# ------------------
# paper_2_plasticity/data_derived/learning_trajectory.rds: one row per scored
# judgement trial, carrying `correct` (0/1), the session/time index, property,
# grammaticality, language, and the participant's z-scored BASELINE (Session 1)
# cognitive predictors (digit span, Stroop interference, ASRT learning). This is the
# analysis-ready DV+predictor table for the joint Part A model in step 04:
#   correct ~ z_session_time * grammatical_property
#           + z_session_time * (z_digit_span + z_stroop + z_asrt + <rs-EEG bands>)
#           + (1 + z_session_time | participant_lab_ID)
# The rs-EEG band predictors are merged at fit time by 04, from the
# resting_state_eeg.rds that 03 writes. The by-participant learning rate and intercept
# are checked for within-sample reliability at the modelling stage (06); a test-retest
# value is not available from a single measurement wave.
#
# USAGE
#   Rscript --vanilla paper_2_plasticity/scripts/02_extract_learning_trajectory.R
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "03_data_manifest.R"))
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  source(here::here("paper_1_transfer", "scripts", "02_extract_accuracy.R"))  # defines build_paper1_accuracy()
  library(dplyr)
})

.les_z <- function(x) {
  s <- stats::sd(x, na.rm = TRUE)
  if (is.na(s) || s == 0) return(rep(0, length(x)))
  as.numeric(scale(x))
}

build_learning_trajectory <- function() {
  # (1) Pooled, validated trial-level grammaticality-judgement accuracy (S2/3/4/6).
  acc <- build_paper1_accuracy() %>%
    mutate(participant_lab_ID = as.integer(as.character(participant_lab_ID)),
           session            = as.integer(as.character(session)),
           session_time       = recoded_session) %>%   # 0,1,2,3 growth-curve coding (S2,3,4,6)
    select(participant_lab_ID, session, session_time, grammatical_property,
           grammaticality, recoded_grammaticality, mini_language, correct)

  # (2) Baseline (Session 1) cognitive predictors, z-scored across participants.
  #
  # STANDARDISATION FRAME. The z-scoring below runs over every participant with a
  # Session-1 battery record, and z_session_time below over the pooled trial frame,
  # both before the join and before step 04's listwise deletion. The frames are
  # therefore slightly wider than the samples the models are fitted to, so "per
  # standard deviation of the predictor" and "the average session" refer to the
  # measured sample rather than to each fitted subset. Restandardising within each
  # fitted frame would change every reported coefficient, so the frame is recorded
  # here rather than changed.
  cog <- readRDS(paper2_derived("cognitive_indices.rds"))
  base_cog <- cog %>%
    filter(session == 1, !is.na(participant_lab_ID)) %>%
    transmute(participant_lab_ID = as.integer(participant_lab_ID),
              z_digit_span = .les_z(digit_span),
              z_stroop     = .les_z(stroop_interference),
              z_asrt       = .les_z(asrt_learning))

  traj <- acc %>%
    left_join(base_cog, by = "participant_lab_ID") %>%
    mutate(z_session_time         = .les_z(session_time),
           grammatical_property   = factor(grammatical_property),
           participant_lab_ID     = factor(participant_lab_ID))

  out <- paper2_derived("learning_trajectory.rds")
  les_assert_readonly_data(out)
  saveRDS(traj, out)
  message(sprintf("[traj] wrote %s (%d judgement trials, %d participants)",
                  out, nrow(traj), dplyr::n_distinct(traj$participant_lab_ID)))
  invisible(traj)
}

# =============================================================================
# Entry point + validation
# =============================================================================
.run <- function() {
  traj <- build_learning_trajectory()
  cat("\n--- learning_trajectory.rds ---\n")
  cat("trials:", nrow(traj), " participants:", dplyr::n_distinct(traj$participant_lab_ID), "\n")

  cat("\nmean judgement accuracy by session (pooled over properties):\n")
  print(traj %>% group_by(session) %>%
          summarise(n = n(), mean_acc = round(mean(correct), 3), .groups = "drop"))

  cat("\nmean accuracy by property x session:\n")
  print(traj %>% group_by(grammatical_property, session) %>%
          summarise(mean_acc = round(mean(correct), 3), .groups = "drop") %>%
          tidyr::pivot_wider(names_from = session, values_from = mean_acc))

  cat("\nbaseline (S1) cognitive-predictor coverage among trajectory participants:\n")
  print(traj %>% distinct(participant_lab_ID, z_digit_span, z_stroop, z_asrt) %>%
          summarise(participants = n(),
                    have_digit_span = sum(!is.na(z_digit_span)),
                    have_stroop = sum(!is.na(z_stroop)),
                    have_asrt = sum(!is.na(z_asrt))))

  cat("\nper-participant x session trial counts (reliability context):\n")
  print(traj %>% count(participant_lab_ID, session) %>%
          summarise(min = min(n), median = stats::median(n), max = max(n)))
  message("[traj] done.")
}

if (sys.nframe() == 0L) .run()
